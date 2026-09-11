/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.emanuelef.remote_capture.netcheck;

import android.net.*;
import android.os.*;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import javax.net.ssl.*;

public final class NetProbe {
    public interface Gate { boolean stopped(); void progress(String text); }
    private final Network network;
    private final NetReport report;
    private final Gate gate;
    private final Set<Socket> sockets=ConcurrentHashMap.newKeySet();
    private final Set<CancellationSignal> signals=ConcurrentHashMap.newKeySet();
    private final ExecutorService dnsExecutor=Executors.newSingleThreadExecutor();
    private final AtomicBoolean cancelled=new AtomicBoolean();
    public static final int BODY_LIMIT=65536;
    public static final int TIMEOUT=6000;
    private final Set<String> permittedHosts=new HashSet<>();
    public NetProbe(Network n,NetReport r,Gate g){network=n;report=r;gate=g;}
    public boolean stopped(){return cancelled.get() || gate.stopped() || Thread.currentThread().isInterrupted();}
    public void close(){cancelled.set(true);for(CancellationSignal s:signals)s.cancel();for(Socket s:sockets)try{s.close();}catch(Exception ignored){}dnsExecutor.shutdownNow();}
    private void check() throws InterruptedIOException {if(stopped())throw new InterruptedIOException("run_stopped");}
    public static URI validate(String s) throws Exception {
        URI u=new URI(s.trim());
        if(!"https".equalsIgnoreCase(u.getScheme()) && !"http".equalsIgnoreCase(u.getScheme()))throw new IllegalArgumentException("Нужен http:// или https://");
        if(u.getHost()==null || u.getUserInfo()!=null || u.getFragment()!=null)throw new IllegalArgumentException("Неверный или приватный URL");
        int p=u.getPort(); if(p!=-1 && p!=80 && p!=443)throw new IllegalArgumentException("Поддерживаются только порты 80 и 443");
        if(u.getRawQuery()!=null)throw new IllegalArgumentException("Для сайтов используйте URL без параметров");
        return u;
    }
    public void run(List<String> urls,boolean detailed) {
        for(String s:urls)try{permittedHosts.add(validate(s).getHost());}catch(Exception ignored){}
        for(String s:urls){
            if(stopped())break;
            try{
                URI u=validate(s);gate.progress("Проверка: "+u.getHost());
                List<InetAddress> ips=new ArrayList<>();
                ips.addAll(dns(u.getHost(),DnsResolver.TYPE_A));
                if(!stopped())ips.addAll(dns(u.getHost(),DnsResolver.TYPE_AAAA));
                boolean v4=false,v6=false; InetAddress first4=null;
                for(InetAddress ip:ips){
                    if(stopped())break;
                    boolean six=ip instanceof Inet6Address;
                    if(six?v6:v4)continue;
                    if(six)v6=true;else{v4=true;first4=ip;}
                    probe(u,ip,"default",true,0,1);
                }
                if(detailed && first4!=null && !stopped() && "https".equalsIgnoreCase(u.getScheme())){
                    probe(u,first4,"TLSv1.2",false,0,1);
                    if(!stopped())probe(u,first4,"TLSv1.3",false,0,1);
                    if(!stopped())probe(u,first4,"no_sni",false,0,1);
                    if(!stopped())probe(u,first4,"default",false,0,2);
                }
            }catch(Exception e){report.result(NetReport.obj("target",s,"stage","setup","status",stopped()?"cancelled":"failed","failure",NetReport.error(e)));}
        }
    }
    private List<InetAddress> dns(String host,int type) {
        long start=SystemClock.elapsedRealtime();
        JSONObject out=NetReport.obj("target",host,"stage","DNS","query_type",type==DnsResolver.TYPE_A?"A":"AAAA","method","Android DnsResolver / selected Network","ttl",null);
        CountDownLatch latch=new CountDownLatch(1);
        AtomicReference<List<InetAddress>> addresses=new AtomicReference<>(Collections.emptyList());
        AtomicReference<String> failure=new AtomicReference<>();AtomicInteger rcode=new AtomicInteger(-1);
        CancellationSignal cancel=new CancellationSignal(); signals.add(cancel);
        try{
            check();
            DnsResolver.getInstance().query(network,host,type,DnsResolver.FLAG_NO_CACHE_LOOKUP|DnsResolver.FLAG_NO_CACHE_STORE,dnsExecutor,cancel,new DnsResolver.Callback<List<InetAddress>>() {
                @Override public void onAnswer(List<InetAddress> a,int rc){addresses.set(a);rcode.set(rc);latch.countDown();}
                @Override public void onError(DnsResolver.DnsException e){failure.set(NetReport.error(e));latch.countDown();}
            });
            boolean done=false;for(int i=0;i<60 && !stopped();i++)if(latch.await(100,TimeUnit.MILLISECONDS)){done=true;break;}
            if(!done){cancel.cancel();failure.set(stopped()?"cancelled":"dns_timeout");}
            out.put("status",failure.get()!=null?(stopped()?"cancelled":"failed"):addresses.get().isEmpty()?"no_answer":"completed");
            out.put("rcode",rcode.get()<0?JSONObject.NULL:rcode.get());out.put("failure",failure.get()==null?JSONObject.NULL:failure.get());
            JSONArray a=new JSONArray();for(InetAddress ip:addresses.get())a.put(ip.getHostAddress());out.put("answers",a);
        }catch(Exception e){try{out.put("status","failed");out.put("failure",NetReport.error(e));}catch(Exception ignored){}}
        finally{signals.remove(cancel);try{out.put("duration_ms",SystemClock.elapsedRealtime()-start);}catch(Exception ignored){}report.result(out);}
        return failure.get()==null?addresses.get():Collections.emptyList();
    }
    private void probe(URI u,InetAddress ip,String variant,boolean http,int redirects,int attempt){
        if(stopped())return;
        String stage="TCP";long start=SystemClock.elapsedRealtime();Socket raw=null,transport=null;
        JSONObject out=NetReport.obj("target",u.toString(),"ip",ip.getHostAddress(),"family",ip instanceof Inet6Address?6:4,"variant",variant,"attempt",attempt,"timeout_ms",TIMEOUT,"cache","new_connection","http_performed",false);
        URI redirect=null;
        try{
            check();int port=u.getPort()<0?("https".equalsIgnoreCase(u.getScheme())?443:80):u.getPort();out.put("port",port);
            raw=network.getSocketFactory().createSocket();sockets.add(raw);raw.setSoTimeout(TIMEOUT);raw.setTcpNoDelay(true);
            report.event("tcp_start",NetReport.obj("host",u.getHost(),"ip",ip.getHostAddress(),"variant",variant));
            raw.connect(new InetSocketAddress(ip,port),TIMEOUT);out.put("tcp_ms",SystemClock.elapsedRealtime()-start);out.put("tcp_success",true);transport=raw;
            if("https".equalsIgnoreCase(u.getScheme())){
                check();stage="TLS";long tlsStart=SystemClock.elapsedRealtime();
                SSLContext context=SSLContext.getInstance("TLS");context.init(null,null,null);
                SSLSocket tls=(SSLSocket)context.getSocketFactory().createSocket(raw,u.getHost(),port,true);transport=tls;sockets.add(tls);tls.setSoTimeout(TIMEOUT);
                SSLParameters p=tls.getSSLParameters();p.setEndpointIdentificationAlgorithm("HTTPS");p.setApplicationProtocols(new String[]{"http/1.1"});
                if("no_sni".equals(variant))p.setServerNames(Collections.emptyList());
                else if(!u.getHost().matches("[0-9.:]+"))p.setServerNames(Collections.singletonList(new SNIHostName(u.getHost())));
                if(variant.startsWith("TLSv")){
                    if(!Arrays.asList(tls.getSupportedProtocols()).contains(variant)){out.put("status","unsupported");out.put("failure","client_tls_version_unsupported");return;}
                    p.setProtocols(new String[]{variant});
                }
                tls.setSSLParameters(p);
                out.put("sni_requested","no_sni".equals(variant)?JSONObject.NULL:u.getHost());
                report.event("tls_start",NetReport.obj("host",u.getHost(),"ip",ip.getHostAddress(),"variant",variant));
                tls.startHandshake();out.put("tls_ms",SystemClock.elapsedRealtime()-tlsStart);out.put("tls_success",true);
                SSLSession session=tls.getSession();out.put("tls_version",session.getProtocol());out.put("cipher_suite",session.getCipherSuite());out.put("alpn",tls.getApplicationProtocol());out.put("certificate_verified",true);
                X509Certificate leaf=(X509Certificate)session.getPeerCertificates()[0];out.put("certificate_sha256",hex(MessageDigest.getInstance("SHA-256").digest(leaf.getEncoded())));out.put("certificate_issuer",leaf.getIssuerX500Principal().getName());
            }
            if(http){
                stage="HTTP";check();long httpStart=SystemClock.elapsedRealtime();
                String path=u.getRawPath()==null || u.getRawPath().isEmpty()?"/":u.getRawPath();
                String host=u.getHost();if(host.contains(":"))host="["+host+"]";if(u.getPort()!=-1)host+=":"+u.getPort();
                String request="GET "+path+" HTTP/1.1\r\nHost: "+host+"\r\nUser-Agent: NetCheck/0.1 (Android diagnostic)\r\nAccept: text/html,*/*;q=0.5\r\nAccept-Encoding: identity\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n";
                transport.getOutputStream().write(request.getBytes(StandardCharsets.US_ASCII));transport.getOutputStream().flush();
                BufferedInputStream in=new BufferedInputStream(transport.getInputStream());
                String status=line(in,8192);if(status==null)throw new EOFException("no_http_status");out.put("http_ttfb_ms",SystemClock.elapsedRealtime()-httpStart);
                String[] parts=status.split(" ",3);if(parts.length<2 || !parts[0].startsWith("HTTP/"))throw new IOException("invalid_http_status");int code=Integer.parseInt(parts[1]);out.put("http_code",code);out.put("http_performed",true);
                Map<String,String> headers=new HashMap<>();int total=0;
                while(true){String h=line(in,8192);if(h==null || h.isEmpty())break;total+=h.length();if(total>65536)throw new IOException("headers_too_large");int colon=h.indexOf(':');if(colon>0)headers.put(h.substring(0,colon).toLowerCase(Locale.ROOT),h.substring(colon+1).trim());}
                out.put("content_type",headers.getOrDefault("content-type",""));out.put("content_length_header",headers.getOrDefault("content-length",""));
                ByteArrayOutputStream body=new ByteArrayOutputStream();long length=-1;try{length=Long.parseLong(headers.getOrDefault("content-length","-1"));}catch(Exception ignored){}
                boolean chunked=headers.getOrDefault("transfer-encoding","").toLowerCase(Locale.ROOT).contains("chunked");
                long until=SystemClock.elapsedRealtime()+TIMEOUT;long remaining=length;boolean eof=false;
                while(body.size()<BODY_LIMIT){
                    check();if(SystemClock.elapsedRealtime()>until)throw new SocketTimeoutException("body_time_budget_exceeded");
                    if(remaining==0){eof=true;break;}
                    long take=chunked?Long.parseLong(Objects.requireNonNull(line(in,512)).split(";",2)[0].trim(),16):remaining<0?BODY_LIMIT-body.size():remaining;
                    if(chunked && take==0){eof=true;break;}
                    while(take>0 && body.size()<BODY_LIMIT){check();byte[] buf=new byte[(int)Math.min(Math.min(take,4096),BODY_LIMIT-body.size())];int n=in.read(buf);if(n<0){if(length>=0||chunked)throw new EOFException("body_ended_early");eof=true;break;}body.write(buf,0,n);take-=n;if(remaining>=0)remaining-=n;if(SystemClock.elapsedRealtime()>until)throw new SocketTimeoutException("body_time_budget_exceeded");}
                    if(eof)break;if(chunked && take==0)line(in,2);if(!chunked && remaining<0 && body.size()==BODY_LIMIT)break;
                }
                byte[] bytes=body.toByteArray();out.put("body_bytes",bytes.length);out.put("body_limit",BODY_LIMIT);out.put("body_truncated",!eof && (length<0 || bytes.length<length));out.put("body_sha256",hex(MessageDigest.getInstance("SHA-256").digest(bytes)));
                String text=new String(bytes,StandardCharsets.UTF_8).toLowerCase(Locale.ROOT);
                boolean challenge=text.contains("slardarwaf")||text.contains("captcha")||text.contains("just a moment")||text.contains("checking your browser");out.put("possible_browser_challenge",challenge);
                out.put("http_ms",SystemClock.elapsedRealtime()-httpStart);
                String location=headers.get("location");
                if(location!=null && code>=300 && code<400){URI candidate=u.resolve(location);out.put("redirect_host",candidate.getHost()==null?JSONObject.NULL:candidate.getHost());if(redirects<2 && permittedHosts.contains(candidate.getHost()) && candidate.getUserInfo()==null && candidate.getQuery()==null && "https".equalsIgnoreCase(candidate.getScheme()))redirect=candidate;else out.put("redirect_not_followed","not_in_selected_targets_or_limit_or_query");}
            }
            out.put("status","completed");out.put("failure",JSONObject.NULL);
        }catch(Exception e){try{out.put("status",stopped()?"cancelled":"failed");out.put("failure",NetReport.error(e));out.put("error_type",e.getClass().getSimpleName());}catch(Exception ignored){}}
        finally{
            for(Socket s:new Socket[]{transport,raw})if(s!=null){sockets.remove(s);try{s.close();}catch(Exception ignored){}}
            try{out.put("stage",stage);out.put("duration_ms",SystemClock.elapsedRealtime()-start);}catch(Exception ignored){}report.result(out);
        }
        if(redirect!=null && !stopped()){
            List<InetAddress> addresses=dns(redirect.getHost(),DnsResolver.TYPE_A);
            if(!addresses.isEmpty())probe(redirect,addresses.get(0),"default",true,redirects+1,1);
        }
    }
    static String line(InputStream in,int max)throws IOException{
        ByteArrayOutputStream b=new ByteArrayOutputStream();int c;
        while((c=in.read())!=-1){if(c=='\n')break;if(c!='\r')b.write(c);if(b.size()>max)throw new IOException("line_too_long");}
        return c==-1 && b.size()==0?null:b.toString(StandardCharsets.US_ASCII.name());
    }
    static String hex(byte[] bytes){StringBuilder b=new StringBuilder();for(byte v:bytes)b.append(String.format(Locale.ROOT,"%02x",v&255));return b.toString();}
}
