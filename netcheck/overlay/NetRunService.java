/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.emanuelef.remote_capture.netcheck;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.net.*;
import android.os.*;
import androidx.core.app.NotificationCompat;
import com.emanuelef.remote_capture.CaptureService;
import com.emanuelef.remote_capture.ConnectionsRegister;
import com.emanuelef.remote_capture.model.ConnectionDescriptor;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

public final class NetRunService extends Service implements NetProbe.Gate {
    public static volatile NetRunService instance;
    public static volatile String status="Готово. Выберите сеть и начните проверку.";
    private static final int NOTICE=9051;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ScheduledExecutorService ticker=Executors.newSingleThreadScheduledExecutor();
    private final Map<Integer,JSONObject> flowMap=new LinkedHashMap<>();
    private volatile boolean cancelled=false,finished=false;
    private volatile String reason="completed";
    private volatile NetProbe probe;
    private volatile NetReport report;
    private volatile boolean ownsCapture=false;
    private Network network;
    private ConnectivityManager cm;
    private ConnectivityManager.NetworkCallback netCallback;
    private ArrayList<String> selectedApps=new ArrayList<>();
    private long deadline;
    private final Map<Integer,String> uidApps=new HashMap<>();
    @Override public IBinder onBind(Intent i){return null;}
    @Override public int onStartCommand(Intent i,int flags,int id){
        if(i!=null && "STOP".equals(i.getAction())){requestStop("cancelled_by_user");return START_NOT_STICKY;}
        if(instance!=null && instance!=this)return START_NOT_STICKY;
        if(instance==this)return START_NOT_STICKY;
        instance=this;
        NotificationManager nm=getSystemService(NotificationManager.class);nm.createNotificationChannel(new NotificationChannel("netcheck_run","Проверка сети",NotificationManager.IMPORTANCE_LOW));
        if(Build.VERSION.SDK_INT>=34)startForeground(NOTICE,notification("Подготовка проверки"),ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);else startForeground(NOTICE,notification("Подготовка проверки"));
        if(i==null){stopSelf();return START_NOT_STICKY;}
        network=i.getParcelableExtra("network");selectedApps=i.getStringArrayListExtra("apps");if(selectedApps==null)selectedApps=new ArrayList<>();ownsCapture=!selectedApps.isEmpty();
        cm=getSystemService(ConnectivityManager.class);deadline=SystemClock.elapsedRealtime()+12*60*1000L;
        netCallback=new ConnectivityManager.NetworkCallback(){@Override public void onLost(Network n){if(n.equals(network))requestStop("network_lost");}};
        cm.registerNetworkCallback(new NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),netCallback);
        new Thread(()->execute(i),"NetCheck-run").start();
        return START_NOT_STICKY;
    }
    private Notification notification(String s){
        Intent open=new Intent(this,NetCheckActivity.class);PendingIntent pi=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Intent stop=new Intent(this,NetRunService.class).setAction("STOP");PendingIntent si=PendingIntent.getService(this,1,stop,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        return new NotificationCompat.Builder(this,"netcheck_run").setSmallIcon(android.R.drawable.stat_notify_sync).setContentTitle("NetCheck · идёт проверка").setContentText(s).setContentIntent(pi).setOngoing(true).addAction(android.R.drawable.ic_media_pause,"Остановить",si).build();
    }
    @Override public void progress(String s){status=s;if(!finished)main.post(()->{if(!finished)getSystemService(NotificationManager.class).notify(NOTICE,notification(s));});}
    @Override public boolean stopped(){return cancelled || finished || SystemClock.elapsedRealtime()>deadline;}
    public void requestStop(String why){if(finished)return;cancelled=true;reason=why;status="Останавливаю и сохраняю отчёт…";NetProbe p=probe;if(p!=null)p.close();main.post(()->{if(AutoService.instance!=null)AutoService.instance.endStep();if(ownsCapture && CaptureService.isServiceActive())CaptureService.stopService();});}
    private void execute(Intent intent){
        try{
            if(network==null || cm.getNetworkCapabilities(network)==null)throw new IllegalStateException("selected_network_unavailable");
            ArrayList<String> urls=intent.getStringArrayListExtra("urls");if(urls==null)urls=new ArrayList<>();
            boolean detailed=intent.getBooleanExtra("detailed",false),automation=intent.getBooleanExtra("automation",false);
            JSONObject settings=NetReport.obj("urls",new JSONArray(urls),"selected_packages",new JSONArray(selectedApps),"detailed",detailed,"automation_requested",automation,"http_body_limit_bytes",NetProbe.BODY_LIMIT,"connection_timeout_ms",NetProbe.TIMEOUT,"approximate_app_byte_limit",50L*1024*1024,"total_time_limit_ms",720000,"app_step_seconds",40);
            report=new NetReport(this,network,intent.getStringExtra("label"),ownsCapture,settings);
            for(String p:selectedApps)try{uidApps.put(getPackageManager().getApplicationInfo(p,0).uid,p);}catch(Exception ignored){}
            if(ownsCapture){
                long until=SystemClock.elapsedRealtime()+15000;while(!CaptureService.isServiceActive() && !stopped() && SystemClock.elapsedRealtime()<until)Thread.sleep(100);
                if(!CaptureService.isServiceActive())throw new IllegalStateException("local_capture_failed_to_start");
                report.event("capture_started",NetReport.obj("dns_server",CaptureService.getDNSServer(),"private_dns_modified",false,"remote_proxy",false));
            }
            ticker.scheduleAtFixedRate(()->{
                try{
                    if(ownsCapture)snapshot();
                    if(SystemClock.elapsedRealtime()>deadline)requestStop("time_limit");
                    if(ownsCapture && CaptureService.getBytes()>50L*1024*1024)requestStop("approximate_traffic_limit");
                    if(ownsCapture && !CaptureService.isServiceActive() && !cancelled)requestStop("local_capture_stopped");
                    if(getSystemService(PowerManager.class)!=null && !getSystemService(PowerManager.class).isInteractive())requestStop("screen_locked_or_off");
                }catch(Exception e){if(report!=null)report.event("monitor_error",NetReport.obj("failure",NetReport.error(e)));requestStop("monitor_error");}
            },1,1,TimeUnit.SECONDS);
            if(!urls.isEmpty() && !stopped()){
                final long webDeadline=SystemClock.elapsedRealtime()+(detailed?600000:360000);
                probe=new NetProbe(network,report,new NetProbe.Gate(){public boolean stopped(){return NetRunService.this.stopped() || SystemClock.elapsedRealtime()>webDeadline;}public void progress(String t){NetRunService.this.progress(t);}});
                probe.run(urls,detailed);probe.close();probe=null;
                if(SystemClock.elapsedRealtime()>webDeadline)report.event("website_budget_reached",NetReport.obj("remaining_tests","may_be_skipped"));
            }
            for(String pkg:selectedApps){
                if(stopped())break;
                String link=pkg.startsWith("org.telegram")?intent.getStringExtra("telegram"):pkg.equals("com.google.android.youtube")?intent.getStringExtra("youtube"):intent.getStringExtra("tiktok");
                String friendly=pkg.startsWith("org.telegram")?"Telegram":pkg.equals("com.google.android.youtube")?"YouTube":"TikTok";
                report.event("app_step_start",NetReport.obj("package",pkg,"planned_action",link==null||link.isEmpty()?"open_home":"open_user_approved_public_link","duration_seconds",40));
                AutoService a=AutoService.instance;
                if(automation && a!=null){
                    CountDownLatch opened=new CountDownLatch(1);AtomicBox launch=new AtomicBox();
                    main.post(()->{try{launch.ok=a.beginStep(pkg,link);}finally{opened.countDown();}});
                    if(!opened.await(5,TimeUnit.SECONDS) || !launch.ok){report.result(NetReport.obj("target",pkg,"stage","APP_AUTOMATION","status","skipped","failure","could_not_open_target_app"));continue;}
                    progress(friendly+": наблюдение 40 секунд. Не трогайте экран.");
                }else{
                    progress("Откройте "+friendly+" вручную. Наблюдение 40 секунд.");
                    report.event("manual_step_required",NetReport.obj("package",pkg,"reason",automation?"accessibility_unavailable":"automation_not_enabled"));
                }
                long end=SystemClock.elapsedRealtime()+40000;
                while(!stopped() && SystemClock.elapsedRealtime()<end){Thread.sleep(500);if(automation && AutoService.instance!=null && AutoService.instance.needsUser)break;}
                JSONObject state=AutoService.instance!=null && automation?AutoService.instance.state():NetReport.obj("observed_ui",false,"manual_required",true);
                report.result(NetReport.obj("target",pkg,"stage","APP_SCENARIO","status",stopped()?"cancelled":"requires_confirmation","ui_observations",state,"failure",null,"note","Сетевые байты и открытие окна не доказывают работу видео или звонков."));
                main.post(()->{if(AutoService.instance!=null)AutoService.instance.endStep();});
                snapshot();
            }
        }catch(Exception e){reason=cancelled?reason:"error";if(report!=null)report.event("run_error",NetReport.obj("failure",NetReport.error(e)));else status="Не удалось начать: "+NetReport.error(e);}
        finally{
            if(probe!=null)probe.close();
            ticker.shutdownNow();
            if(ownsCapture){try{snapshot();}catch(Exception ignored){}main.post(()->{if(CaptureService.isServiceActive())CaptureService.stopService();});}
            if(SystemClock.elapsedRealtime()>deadline && !cancelled)reason="time_limit";
            try{if(report!=null)report.finish(reason);}catch(Exception e){status="Ошибка сохранения: "+NetReport.error(e);}
            finished=true;
            if(report!=null)status="Отчёт сохранён · "+reason+". Открой «Результаты и отправка ZIP».";
            main.post(()->{if(AutoService.instance!=null)AutoService.instance.endStep();stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();});
        }
    }
    private static final class AtomicBox{volatile boolean ok;}
    private synchronized void snapshot(){
        if(report==null)return;ConnectionsRegister reg=CaptureService.getConnsRegister();if(reg==null)return;
        int lost;
        synchronized(reg){
            int count=reg.getConnCount();lost=reg.getUntrackedConnCount();
            for(int i=0;i<count;i++){
                ConnectionDescriptor c=reg.getConn(i);if(c==null)continue;
                String app=uidApps.get(c.uid);if(app==null)continue;
                String host=c.info!=null && c.info.matches("[A-Za-z0-9_.-]{1,253}")?c.info:null;
                flowMap.put(c.incr_id,NetReport.obj("id",c.incr_id,"package",app,"ip_version",c.ipver,"ip_protocol",c.ipproto,"destination_ip",c.dst_ip,"destination_port",c.dst_port,"hostname_if_visible",host,"detected_protocol",c.l7proto,"sent_bytes",c.sent_bytes,"received_bytes",c.rcvd_bytes,"sent_packets_local_view",c.sent_pkts,"received_packets_local_view",c.rcvd_pkts,"native_status",c.status,"native_socket_error",c.error,"first_seen_native",c.first_seen,"last_seen_native",c.last_seen,"snapshot_utc",java.time.Instant.now().toString()));
                if(flowMap.size()>10000){Integer k=flowMap.keySet().iterator().next();flowMap.remove(k);lost++;}
            }
        }
        report.flows(new JSONArray(new ArrayList<>(flowMap.values())),lost);
    }
    public void automationEvent(String kind,JSONObject detail){NetReport r=report;if(r!=null&&!finished)r.event(kind,detail);}
    @Override public void onDestroy(){if(!finished)requestStop("service_destroyed");try{if(cm!=null && netCallback!=null)cm.unregisterNetworkCallback(netCallback);}catch(Exception ignored){}ticker.shutdownNow();if(instance==this)instance=null;super.onDestroy();}
}
