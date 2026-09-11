/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.emanuelef.remote_capture.netcheck;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.net.Uri;
import android.os.*;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import org.json.JSONObject;
import java.util.*;

/** Deterministic, foreground-only assistance. Never records text or entire UI trees. */
public final class AutoService extends AccessibilityService {
    public static volatile AutoService instance;
    public volatile boolean needsUser;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private volatile String target;
    private volatile boolean observed,playFound,playClicked,pausedControlFound;
    private volatile int inspections;
    private long began;
    private final Runnable tick=new Runnable(){public void run(){if(target!=null){inspect();handler.postDelayed(this,1000);}}};
    @Override protected void onServiceConnected(){instance=this;}
    public boolean beginStep(String pkg,String link){
        endStep();
        if(NetRunService.instance==null || NetRunService.instance.stopped())return false;
        boolean known=false;for(String[] group:NetCheckActivity.PACKAGES)if(Arrays.asList(group).contains(pkg))known=true;
        if(!known)return false;
        target=pkg;observed=false;playFound=false;playClicked=false;pausedControlFound=false;needsUser=false;inspections=0;began=SystemClock.elapsedRealtime();
        try{
            Intent i;
            if(link!=null&&!link.isEmpty())i=new Intent(Intent.ACTION_VIEW,Uri.parse(link)).setPackage(pkg);
            else i=getPackageManager().getLaunchIntentForPackage(pkg);
            if(i==null){endStep();return false;}
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);startActivity(i);handler.postDelayed(tick,1500);return true;
        }catch(Exception e){NetRunService.instance.automationEvent("app_launch_failed",NetReport.obj("package",pkg,"failure",NetReport.error(e)));endStep();return false;}
    }
    @Override public void onAccessibilityEvent(AccessibilityEvent event){
        // Event text is deliberately never read or recorded.
        if(target==null || event.getPackageName()==null || !target.contentEquals(event.getPackageName()))return;
        if(event.getEventType()==AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED)observed=true;
    }
    private void inspect(){
        String pkg=target;
        if(pkg==null || NetRunService.instance==null || NetRunService.instance.stopped()){endStep();return;}
        AccessibilityNodeInfo root=getRootInActiveWindow();
        if(root==null)return;
        try{
            if(root.getPackageName()==null || !pkg.contentEquals(root.getPackageName())){
                if(SystemClock.elapsedRealtime()-began>10000){needsUser=true;NetRunService.instance.automationEvent("app_needs_user",NetReport.obj("package",pkg,"reason","target_app_not_foreground"));}
                return;
            }
            observed=true;inspections++;
            ArrayDeque<AccessibilityNodeInfo> q=new ArrayDeque<>();q.add(root);int count=0;
            while(!q.isEmpty() && count++<180){
                AccessibilityNodeInfo n=q.removeFirst();
                try{
                    if(n.isPassword())needsUser=true;
                    String id=n.getViewIdResourceName();
                    if(id!=null){String low=id.toLowerCase(Locale.ROOT);if(low.contains("captcha")||low.endsWith("/phone_number")||low.endsWith("/login_password"))needsUser=true;}
                    // Only YouTube has a click rule. No arbitrary text search, swipes, typing or message actions.
                    if("com.google.android.youtube".equals(pkg) && id!=null && (id.endsWith("/player_control_play_pause_replay_button")||id.endsWith("/play_pause_button"))){
                        CharSequence desc=n.getContentDescription();String control=desc==null?"":desc.toString().trim().toLowerCase(Locale.ROOT);
                        if(control.equals("pause")||control.equals("приостановить")||control.equals("пауза"))pausedControlFound=true;
                        if(control.equals("play")||control.equals("воспроизвести")){
                            playFound=true;
                            if(!needsUser && !playClicked && n.isEnabled() && n.isClickable()){
                                playClicked=n.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                                NetRunService.instance.automationEvent("known_play_control",NetReport.obj("package",pkg,"click_accepted",playClicked));
                            }
                        }
                    }
                    for(int j=0;j<n.getChildCount();j++){AccessibilityNodeInfo child=n.getChild(j);if(child!=null)q.addLast(child);}
                }finally{if(n!=root)n.recycle();}
            }
            while(!q.isEmpty()){AccessibilityNodeInfo n=q.removeFirst();if(n!=root)n.recycle();}
            if(needsUser)NetRunService.instance.automationEvent("app_needs_user",NetReport.obj("package",pkg,"reason","login_password_or_challenge_control"));
        }finally{root.recycle();}
    }
    public JSONObject state(){return NetReport.obj("target_app_observed",observed,"inspections",inspections,"known_play_control_found",playFound,"play_click_accepted",playClicked,"pause_control_observed",pausedControlFound,"needs_user",needsUser,"video_playback_confirmed",JSONObject.NULL,"reason","UI controls are not proof of decoded video or audio");}
    public void endStep(){target=null;handler.removeCallbacks(tick);}
    @Override public void onInterrupt(){endStep();}
    @Override public void onDestroy(){endStep();if(instance==this)instance=null;super.onDestroy();}
}
