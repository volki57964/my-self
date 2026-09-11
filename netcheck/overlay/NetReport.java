/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.emanuelef.remote_capture.netcheck;

import android.content.Context;
import android.net.*;
import android.os.*;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Instant;
import java.util.*;
import java.util.zip.*;

public final class NetReport {
    public final File dir;
    public final JSONObject root = new JSONObject();
    private final JSONArray results = new JSONArray();
    private long origin = SystemClock.elapsedRealtime();
    public final String id;
    public static JSONObject obj(Object... pairs) {
        JSONObject o = new JSONObject();
        for (int i=0;i+1<pairs.length;i+=2) try { o.put(String.valueOf(pairs[i]), pairs[i+1] == null ? JSONObject.NULL : pairs[i+1]); } catch (JSONException e) { throw new IllegalArgumentException(e); }
        return o;
    }
    public static String error(Throwable t) {
        if (t == null) return "unknown";
        String s=t.getClass().getSimpleName()+": "+String.valueOf(t.getMessage());
        return s.substring(0,Math.min(s.length(),400));
    }
    public static File base(Context c) { File f=new File(c.getFilesDir(),"netcheck-reports"); f.mkdirs(); return f; }
    public NetReport(Context c, Network network, String label, boolean captured, JSONObject settings) throws Exception {
        id=Instant.now().toString().replace(':','-')+"-"+UUID.randomUUID().toString().substring(0,8);
        dir=new File(base(c),id); if(!dir.mkdirs()) throw new IOException("Cannot create report directory");
        ConnectivityManager cm=c.getSystemService(ConnectivityManager.class);
        NetworkCapabilities cap=cm.getNetworkCapabilities(network);
        LinkProperties lp=cm.getLinkProperties(network);
        String type=cap==null?"unknown":cap.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)?"wifi":cap.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)?"mobile":"other";
        JSONArray dns=new JSONArray(); if(lp!=null) for(java.net.InetAddress a:lp.getDnsServers()) dns.put(a.getHostAddress());
        root.put("schema_version","1.0"); root.put("app_version","0.1-pilot"); root.put("run_id",id);
        root.put("started_utc",Instant.now().toString()); root.put("timezone",TimeZone.getDefault().getID());
        root.put("android_sdk",Build.VERSION.SDK_INT); root.put("android_version",Build.VERSION.RELEASE);
        root.put("network_type",type); root.put("network_label",label); root.put("dns_servers",dns);
        root.put("private_dns_active",lp!=null && lp.isPrivateDnsActive()); root.put("network_validated",cap!=null && cap.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED));
        root.put("local_vpn_capture",captured); root.put("external_vpn_detected_at_start",false);
        root.put("settings",settings); root.put("status","running"); root.put("results",results);
        root.put("limitations",new JSONArray(Arrays.asList("Нет независимой контрольной точки за пределами этой сети.","Сбой не доказывает вмешательство РКН, конкретный пакет или белый список.","Локальный VPN изменяет сетевой путь и TCP-стек; сравнивайте с работой без захвата.","Метаданные соединений не доказывают воспроизведение видео или слышимость звонка.","Нет расшифровки TLS, записи экрана, личной переписки или аудио.","Проверки QUIC-handshake, DoH и разбиения ClientHello в этой пилотной версии не реализованы; UDP приложений пересылается ядром.","Счётчик ограничения трафика приблизительный; измеряется раз в секунду, возможен небольшой перерасход.")));
        checkpoint(); event("run_started",obj("network_type",type));
    }
    public synchronized void result(JSONObject v) { results.put(v); event("result",v); checkpoint(); }
    public synchronized void event(String kind, JSONObject detail) {
        JSONObject e=obj("utc",Instant.now().toString(),"elapsed_ms",SystemClock.elapsedRealtime()-origin,"event",kind,"details",detail);
        try(FileOutputStream f=new FileOutputStream(new File(dir,"events.jsonl"),true)) { f.write((e.toString()+"\n").getBytes(StandardCharsets.UTF_8)); }
        catch(IOException ex){ throw new IllegalStateException("Cannot save event",ex); }
    }
    public synchronized void flows(JSONArray flows, int lost) {
        try { root.put("app_connections",flows); root.put("capture_untracked_connections",lost); } catch(JSONException e){throw new IllegalStateException(e);}
        checkpoint();
    }
    public synchronized void finish(String status) {
        try { root.put("status",status); root.put("ended_utc",Instant.now().toString()); root.put("duration_ms",SystemClock.elapsedRealtime()-origin); } catch(JSONException e){throw new IllegalStateException(e);}
        event("run_finished",obj("status",status)); checkpoint();
    }
    public synchronized void checkpoint() {
        try { atomic(new File(dir,"report.json"),root.toString(2)); atomic(new File(dir,"summary.txt"),summary(root)); }
        catch(Exception e){throw new IllegalStateException("Cannot save report",e);}
    }
    public static void atomic(File file,String text) throws IOException {
        File temp=new File(file.getParentFile(),file.getName()+".tmp");
        try(FileOutputStream out=new FileOutputStream(temp)){out.write(text.getBytes(StandardCharsets.UTF_8));out.getFD().sync();}
        java.nio.file.Files.move(temp.toPath(),file.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING);
    }
    public static String summary(JSONObject r) {
        StringBuilder b=new StringBuilder("NETCHECK · ТЕСТОВАЯ ВЕРСИЯ 0.1\n\n");
        b.append("Сеть: ").append(r.optString("network_type")).append(" · ").append(r.optString("network_label")).append("\n");
        b.append("Начало UTC: ").append(r.optString("started_utc")).append("\nСостояние: ").append(r.optString("status")).append("\n\n");
        JSONArray a=r.optJSONArray("results");
        if(a!=null) for(int i=0;i<a.length();i++) {JSONObject v=a.optJSONObject(i);if(v!=null)b.append(v.optString("target")).append(" · ").append(v.optString("stage")).append(" · ").append(v.optString("status")).append(" · ").append(v.optString("failure","")).append("\n");}
        JSONArray f=r.optJSONArray("app_connections"); b.append("\nСоединений выбранных приложений: ").append(f==null?0:f.length()).append("\n");
        b.append("\nАвтоматизация экрана и успешные байты не подтверждают работу всех функций.\nПодробности: report.json и events.jsonl.\nОтчёт не публикуется автоматически.\n");
        return b.toString();
    }
    public static File[] reports(Context c) {
        File[] a=base(c).listFiles(f->f.isDirectory() && new File(f,"report.json").isFile());
        if(a==null)return new File[0]; Arrays.sort(a,Comparator.comparing(File::getName).reversed()); return a;
    }
    public static File zip(Context c, File[] dirs) throws IOException {
        File outDir=new File(c.getCacheDir(),"netcheck-export");outDir.mkdirs();
        File[] old=outDir.listFiles();if(old!=null)for(File f:old)if(System.currentTimeMillis()-f.lastModified()>86400000L)f.delete();
        File zip=new File(outDir,"NetCheck-"+System.currentTimeMillis()+".zip");
        try(ZipOutputStream z=new ZipOutputStream(new FileOutputStream(zip))) {
            for(File d:dirs)for(String name:new String[]{"report.json","summary.txt","events.jsonl"}) {
                File f=new File(d,name);if(!f.isFile())continue;
                z.putNextEntry(new ZipEntry(d.getName()+"/"+name));Files.copy(f.toPath(),z);z.closeEntry();
            }
        }
        return zip;
    }
}
