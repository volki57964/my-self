/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.emanuelef.remote_capture.netcheck;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.*;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;
import androidx.activity.ComponentActivity;
import androidx.core.content.FileProvider;
import androidx.preference.PreferenceManager;
import com.emanuelef.remote_capture.CaptureHelper;
import com.emanuelef.remote_capture.CaptureService;
import com.emanuelef.remote_capture.model.*;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;

public final class NetCheckActivity extends ComponentActivity {
    static final String[] DEFAULT_URLS={"https://example.com/","https://ya.ru/","https://web.telegram.org/","https://telegram.org/","https://www.youtube.com/","https://www.tiktok.com/","https://www.instagram.com/","https://www.facebook.com/","https://x.com/","https://twitter.com/","https://max.ru/","https://rutube.ru/","https://www.google.com/"};
    public static final String[][] PACKAGES={{"org.telegram.messenger","org.telegram.messenger.web"},{"com.google.android.youtube"},{"com.zhiliaoapp.musically","com.ss.android.ugc.trill"}};
    static final String[] APP_NAMES={"Telegram","YouTube","TikTok"};
    private LinearLayout layout;
    private EditText label,urls,youtube,telegram,tiktok;
    private CheckBox sites,detail,apps;
    private final CheckBox[] selected=new CheckBox[3];
    private TextView status;
    private CaptureHelper helper;
    private Network pendingNetwork;
    private ArrayList<String> pendingApps;
    private Intent pendingRun;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private File export;
    private final Runnable updater=new Runnable(){public void run(){if(status!=null){ConnectivityManager c=getSystemService(ConnectivityManager.class);Network n=c.getActiveNetwork();NetworkCapabilities cap=c.getNetworkCapabilities(n);String net=cap==null?"Сеть не найдена":cap.hasTransport(NetworkCapabilities.TRANSPORT_VPN)?"VPN / локальное наблюдение":cap.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)?"Wi-Fi":"Мобильная / другая сеть";status.setText(net+"\n"+NetRunService.status);}handler.postDelayed(this,1000);}};
    @Override public void onCreate(Bundle b){
        super.onCreate(b);getWindow().setStatusBarColor(Color.rgb(12,20,33));getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        helper=new CaptureHelper(this);helper.setListener(ok->{if(ok && pendingRun!=null)launchRun();else toast("Не удалось включить локальную диагностику.");});
        ScrollView scroll=new ScrollView(this);layout=new LinearLayout(this);layout.setOrientation(1);layout.setPadding(dp(20),dp(28),dp(20),dp(32));layout.setBackgroundColor(Color.rgb(12,20,33));scroll.addView(layout);setContentView(scroll);
        title("NetCheck",30);text("ДИАГНОСТИКА СЕТИ · ПИЛОТ 0.1",12,0xFF77B9F2);
        status=text("Готово к проверке",16,Color.WHITE);status.setPadding(0,dp(18),0,dp(18));
        label=edit("Подпись: Wi-Fi Ростелеком / МТС","",false);
        sites=check("Проверить сайты: DNS → TCP → TLS → HTTP",true);
        urls=edit("Адреса, по одному в строке",String.join("\n",DEFAULT_URLS),true);urls.setMinLines(3);urls.setMaxLines(6);
        detail=check("Подробно: версии TLS, без SNI, повтор",false);
        text("Прямые тесты выполняются с этого телефона. Ошибка не равна доказанной блокировке. До 6 мин; тело ответа ≤64 КиБ.",13,0xFFABBCCC);
        space();apps=check("Проверить установленные приложения",false);
        for(int i=0;i<3;i++){selected[i]=check(APP_NAMES[i],true);}
        youtube=edit("Публичное тестовое видео YouTube","https://www.youtube.com/watch?v=jNQXAC9IVRw",false);
        telegram=edit("Публичный канал Telegram","https://t.me/telegram",false);
        tiktok=edit("Публичная ссылка TikTok (необязательно)","",false);
        text("Только выбранные приложения. Локальное наблюдение без удалённого VPN, расшифровки и отправки данных. Оно может влиять на соединения. Ссылки могут попасть в историю приложения.",13,0xFFABBCCC);
        button("Разрешить автоматические действия",()->new AlertDialog.Builder(this).setTitle("Специальные возможности").setMessage("Необязательно. NetCheck открывает только подтверждённые приложения и пытается нажать точную кнопку воспроизведения YouTube. Нет сообщений, звонков, лайков, подписок, ввода паролей и записи экрана. Неизвестный экран требует участия человека. Разрешение можно выключить после проверки.").setPositiveButton("Открыть настройки",(d,w)->startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))).setNegativeButton("Отмена",null).show(),false);
        text("Без этого разрешения доступно ручное использование приложений с тем же сбором метаданных. Автопроверка не гарантирует, что видео действительно играло; звук звонков не тестируется.",13,0xFFABBCCC);
        space();button("Начать проверку",this::confirm,true);
        button("Остановить",()->{if(NetRunService.instance!=null)NetRunService.instance.requestStop("cancelled_by_user");else if(CaptureService.isServiceActive())CaptureService.stopService();},false);
        button("Результаты и отправка ZIP",this::history,false);
        button("О приложении и приватность",()->new AlertDialog.Builder(this).setTitle("NetCheck 0.1 · экспериментальная сборка").setMessage("Основано на PCAPdroid, GPL-3.0-or-later. Авторы ядра: Emanuele Faranda и участники проекта.\n\nНет аналитики, рекламы, загрузки отчётов, фонового запуска при включении телефона, root или TLS MITM. Сеть может видеть тестовые обращения. Данные хранятся локально до удаления. Выбирайте «Поделиться», чтобы отправить ZIP лично.\n\nОтчёт содержит адреса серверов, время, подпись сети и ошибки. Он не раскрывает внутренние правила фильтра. DoH, тест QUIC-handshake и фрагментация ClientHello в этом пилоте отсутствуют.\n\nИсходники и лицензии публикуются вместе с APK. Ядро локального захвата может иначе обрабатывать TCP и DNS, чем Android без наблюдения. Сравните с обычной работой приложений.").setPositiveButton("Понятно",null).show(),false);
    }
    @Override protected void onResume(){super.onResume();handler.post(updater);}
    @Override protected void onPause(){handler.removeCallbacks(updater);super.onPause();}
    private void confirm(){
        if(NetRunService.instance!=null){toast("Проверка уже идёт.");return;}
        if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED){requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},101);toast("Разреши уведомления, затем нажми «Начать» ещё раз.");return;}
        ConnectivityManager cm=getSystemService(ConnectivityManager.class);pendingNetwork=cm.getActiveNetwork();NetworkCapabilities cap=cm.getNetworkCapabilities(pendingNetwork);
        if(pendingNetwork==null || cap==null){toast("Подключись к Wi-Fi или мобильной сети.");return;}
        if(cap.hasTransport(NetworkCapabilities.TRANSPORT_VPN)){toast("Сначала отключи другой VPN. Поверх VPN этот прогон не запускается.");return;}
        ArrayList<String> targets=new ArrayList<>();
        if(sites.isChecked())try{for(String line:urls.getText().toString().split("\\s+"))if(!line.trim().isEmpty()){if(targets.size()>=20)throw new Exception("Не более 20 адресов");targets.add(NetProbe.validate(line).toString());}}catch(Exception e){toast(e.getMessage());return;}
        pendingApps=new ArrayList<>();if(apps.isChecked())for(int i=0;i<3;i++)if(selected[i].isChecked())for(String pkg:PACKAGES[i])try{getPackageManager().getPackageInfo(pkg,0);pendingApps.add(pkg);break;}catch(PackageManager.NameNotFoundException ignored){}
        if(targets.isEmpty() && pendingApps.isEmpty()){toast("Нет выбранных сайтов или установленных приложений.");return;}
        String yt=youtube.getText().toString().trim(),tg=telegram.getText().toString().trim(),tt=tiktok.getText().toString().trim();
        if(!safeLink(yt,"youtube.com","www.youtube.com","youtu.be") || !safeLink(tg,"t.me") || !safeLink(tt,"tiktok.com","www.tiktok.com","vm.tiktok.com","vt.tiktok.com")){toast("Используй публичные https-ссылки выбранных сервисов без логина и пароля.");return;}
        pendingRun=new Intent(this,NetRunService.class).putExtra("network",pendingNetwork).putExtra("label",label.getText().toString()).putStringArrayListExtra("urls",targets).putStringArrayListExtra("apps",pendingApps).putExtra("detailed",detail.isChecked()).putExtra("youtube",yt).putExtra("telegram",tg).putExtra("tiktok",tt).putExtra("automation",AutoService.instance!=null);
        String plan="Сайтов: "+targets.size()+". Приложений: "+pendingApps.size()+".\n\n"+(pendingApps.isEmpty()?"":"Приложения откроются по очереди примерно на 40 секунд. TikTok без ссылки откроет главную ленту. Только просмотр, без отправки сообщений.\n\n")+"Провайдер может видеть проверки. Отчёты остаются на телефоне. Возможен расход до ~50 МиБ и влияние локального VPN на соединения. Не блокируй экран. Можно остановить в уведомлении.";
        new AlertDialog.Builder(this).setTitle("Разрешить этот прогон?").setMessage(plan).setNegativeButton("Отмена",null).setPositiveButton("Начать",(d,w)->{
            if(pendingApps.isEmpty()){launchRun();return;}
            android.content.SharedPreferences p=PreferenceManager.getDefaultSharedPreferences(this);
            p.edit().putBoolean(Prefs.PREF_MALWARE_DETECTION,false).putBoolean(Prefs.PREF_FIREWALL,false).putBoolean(Prefs.PREF_USE_SYSTEM_DNS,true).putBoolean(Prefs.PREF_RESTART_ON_DISCONNECT,false).putBoolean(Prefs.PREF_START_AT_BOOT,false).putBoolean(Prefs.PREF_PORT_MAPPING_ENABLED,false).apply();
            CaptureSettings s=new CaptureSettings(this,p);s.app_filter=new HashSet<>(pendingApps);s.dump_mode=Prefs.DumpMode.NONE;s.socks5_enabled=false;s.tls_decryption=false;s.full_payload=false;s.root_capture=false;s.api_capture=true;s.auto_block_private_dns=false;s.block_quic_mode=Prefs.BlockQuicMode.NEVER;s.ip_mode=Prefs.IpMode.BOTH;s.pcapng_format=false;s.input_pcap_path=null;
            helper.startCapture(s);
        }).show();
    }
    private boolean safeLink(String s,String... allowed){if(s.isEmpty())return true;try{java.net.URI u=new java.net.URI(s);if(!"https".equalsIgnoreCase(u.getScheme()) || u.getUserInfo()!=null || u.getPort()!=-1)return false;return Arrays.asList(allowed).contains(u.getHost());}catch(Exception e){return false;}}
    private void launchRun(){try{startForegroundService(pendingRun);}catch(Exception e){if(CaptureService.isServiceActive())CaptureService.stopService();toast(NetReport.error(e));}pendingRun=null;}
    private void history(){File[] files=NetReport.reports(this);if(files.length==0){toast("Отчётов пока нет.");return;}String[] names=new String[files.length];for(int i=0;i<files.length;i++)try{JSONObject r=new JSONObject(Files.readString(new File(files[i],"report.json").toPath()));names[i]=r.optString("network_type")+" · "+r.optString("network_label")+"\n"+r.optString("started_utc")+" · "+r.optString("status");}catch(Exception e){names[i]=files[i].getName();}
        new AlertDialog.Builder(this).setTitle("Локальные отчёты").setItems(names,(d,w)->reportMenu(files[w])).setPositiveButton("Отправить все ZIP",(d,w)->share(files)).setNegativeButton("Закрыть",null).show();}
    private void reportMenu(File f){new AlertDialog.Builder(this).setTitle(f.getName()).setItems(new String[]{"Отправить ZIP","Сохранить ZIP в файлы","Посмотреть итог","Удалить этот отчёт"},(d,w)->{
        if(w==0)share(new File[]{f});
        else if(w==1)new Thread(()->{try{export=NetReport.zip(this,new File[]{f});runOnUiThread(()->{Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/zip").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,export.getName());startActivityForResult(i,102);});}catch(Exception e){runOnUiThread(()->toast(NetReport.error(e)));}}).start();
        else if(w==2)try{String s=Files.readString(new File(f,"summary.txt").toPath());new AlertDialog.Builder(this).setTitle("Итог").setMessage(s).setPositiveButton("Закрыть",null).show();}catch(Exception e){toast(NetReport.error(e));}
        else new AlertDialog.Builder(this).setMessage("Удалить локальный отчёт?").setNegativeButton("Нет",null).setPositiveButton("Удалить",(dd,ww)->{if(NetRunService.instance!=null){toast("Сначала останови проверку.");return;}File[] a=f.listFiles();if(a!=null)for(File q:a)q.delete();f.delete();}).show();
    }).show();}
    private void share(File[] files){new Thread(()->{try{File zip=NetReport.zip(this,files);Uri uri=FileProvider.getUriForFile(this,getPackageName()+".netcheck.files",zip);runOnUiThread(()->{Intent i=new Intent(Intent.ACTION_SEND).setType("application/zip").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);i.setClipData(ClipData.newRawUri("NetCheck ZIP",uri));startActivity(Intent.createChooser(i,"Отправить отчёт лично"));});}catch(Exception e){runOnUiThread(()->toast(NetReport.error(e)));}}).start();}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==102 && result==RESULT_OK && data!=null && data.getData()!=null && export!=null){Uri uri=data.getData();File f=export;new Thread(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("No output stream");Files.copy(f.toPath(),out);runOnUiThread(()->toast("ZIP сохранён"));}catch(Exception e){runOnUiThread(()->toast(NetReport.error(e)));}}).start();}}
    private int dp(int n){return (int)(n*getResources().getDisplayMetrics().density+.5f);}
    private void space(){View v=new View(this);layout.addView(v,new LinearLayout.LayoutParams(1,dp(14)));}
    private TextView text(String t,int size,int color){TextView v=new TextView(this);v.setText(t);v.setTextSize(size);v.setTextColor(color);v.setPadding(0,dp(5),0,dp(5));layout.addView(v);return v;}
    private void title(String s,int size){TextView v=text(s,size,Color.WHITE);v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);}
    private EditText edit(String hint,String val,boolean multiline){EditText v=new EditText(this);v.setHint(hint);v.setText(val);v.setTextSize(14);v.setTextColor(Color.WHITE);v.setHintTextColor(0xFFABBCCC);v.setPadding(dp(12),dp(10),dp(12),dp(10));v.setSingleLine(!multiline);v.setGravity(Gravity.TOP);v.setBackground(bg(0xFF18293D));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.setMargins(0,dp(8),0,dp(8));layout.addView(v,p);return v;}
    private CheckBox check(String s,boolean checked){CheckBox c=new CheckBox(this);c.setText(s);c.setTextColor(Color.WHITE);c.setTextSize(14);c.setChecked(checked);layout.addView(c);return c;}
    private GradientDrawable bg(int c){GradientDrawable d=new GradientDrawable();d.setColor(c);d.setCornerRadius(dp(12));return d;}
    private void button(String s,Runnable r,boolean primary){Button b=new Button(this);b.setText(s);b.setAllCaps(false);b.setTextColor(primary?0xFF091726:Color.WHITE);b.setTextSize(15);b.setBackground(bg(primary?0xFF8AC9FC:0xFF243850));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(52));p.setMargins(0,dp(7),0,dp(7));layout.addView(b,p);b.setOnClickListener(v->r.run());}
    private void toast(String s){Toast.makeText(this,s,Toast.LENGTH_LONG).show();}
}
