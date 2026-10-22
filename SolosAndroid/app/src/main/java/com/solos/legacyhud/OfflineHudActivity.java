package com.solos.legacyhud;

import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.hardware.*;
import android.location.*;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.*;
import android.speech.*;
import android.view.*;
import android.widget.*;
import com.google.mlkit.common.model.DownloadConditions;
import com.google.mlkit.nl.translate.*;
import java.io.*;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.*;

public class OfflineHudActivity extends Activity implements SensorEventListener, LocationListener {
  private final Handler ui=new Handler(Looper.getMainLooper());
  private final ExecutorService worker=Executors.newSingleThreadExecutor();
  private BluetoothAdapter adapter;
  private BluetoothSocket socket;
  private OutputStream output;
  private volatile boolean connected=false;
  private volatile boolean running=true;
  private Spinner paired;
  private TextView status,details,rxDisplay;
  private EditText tempEntry,conditionEntry;
  private final ArrayList<BluetoothDevice> devices=new ArrayList<>();
  private android.content.SharedPreferences prefs;
  private SensorManager sensors;
  private LocationManager location;
  private int steps=-1,stepBase=-1;
  private double tripMeters=0,speedMps=0,latitude=0,longitude=0;
  private boolean gps=false;
  private Location previousFix;
  private int mode=0;
  private String caption="";
  private String stateMessage="Ready";
  private String lastIncoming="No incoming buttons detected yet";
  private String learnedSignature="";
  private long learningUntil=0, lastSendAt=0,lastButtonAt=0,lastFrameAt=0;
  private SpeechRecognizer recognizer;
  private Translator translator;
  private boolean voiceWanted=false;
  private MediaSession mediaSession;
  private String weather="",weatherLabel="NO LIVE WEATHER WITHOUT INTERNET";
  private Runnable ticker;
  private boolean sensorRegistered=false;
  private boolean gpsRegistered=false;

  @Override public void onCreate(Bundle saved){
    super.onCreate(saved);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    prefs=getSharedPreferences("offline_hud",MODE_PRIVATE);
    adapter=BluetoothAdapter.getDefaultAdapter();
    sensors=(SensorManager)getSystemService(SENSOR_SERVICE);
    location=(LocationManager)getSystemService(LOCATION_SERVICE);
    learnedSignature=prefs.getString("button_signature","");
    weather=prefs.getString("weather","");
    weatherLabel=prefs.getString("weather_label","NO LIVE WEATHER WITHOUT INTERNET");
    ScrollView scroll=new ScrollView(this);
    LinearLayout root=new LinearLayout(this);root.setPadding(24,20,24,30);root.setOrientation(LinearLayout.VERTICAL);
    scroll.addView(root);setContentView(scroll);
    TextView heading=new TextView(this);heading.setText("SOLOS LEGACY HUD v2\n100% offline HUD mode");heading.setTextSize(24);root.addView(heading);
    status=new TextView(this);status.setPadding(0,12,0,12);root.addView(status);
    paired=new Spinner(this);root.addView(paired);
    add(root,"Refresh paired glasses",v->refresh());
    add(root,"CONNECT TO SOLOS",v->connect());
    add(root,"DASHBOARD  •  TIME, GPS, STEPS",v->switchMode(0));
    add(root,"CAPTIONS  •  ENGLISH",v->switchMode(1));
    add(root,"TRANSLATOR  •  SPANISH TO ENGLISH",v->switchMode(2));
    add(root,"NEXT HUD MODE  (+)",v->nextMode("Phone button"));
    add(root,"PREPARE OFFLINE SPEECH PACKS",v->prepareSpeechPacks());
    add(root,"DOWNLOAD SPANISH-ENGLISH MODEL (Wi-Fi ONCE)",v->downloadTranslationModel());
    TextView label=new TextView(this);
    label.setText("\nWEATHER CACHE (manual entry)\nNo phone can know live outdoor weather in airplane mode without a weather sensor or saved report. Enter the last known weather if wanted.");
    root.addView(label);
    tempEntry=new EditText(this);tempEntry.setSingleLine(true);tempEntry.setHint("Temperature e.g. 82 F");tempEntry.setText(prefs.getString("weather_temp",""));root.addView(tempEntry);
    conditionEntry=new EditText(this);conditionEntry.setSingleLine(true);conditionEntry.setHint("Condition e.g. Sunny");conditionEntry.setText(prefs.getString("weather_condition",""));root.addView(conditionEntry);
    add(root,"SAVE LAST KNOWN WEATHER",v->saveWeather());
    add(root,"RESET TRIP DISTANCE",v->{tripMeters=0;previousFix=null;showState("Trip distance reset");redraw(true);});
    add(root,"LEARN + BUTTON SIGNAL (8 SEC)",v->{learningUntil=SystemClock.elapsedRealtime()+8000;showState("Now press + on your glasses. Any incoming RFCOMM packet will be recorded as a candidate.");});
    add(root,"CLEAR LEARNED BUTTON",v->{learnedSignature="";prefs.edit().remove("button_signature").apply();showState("Button mapping cleared");});
    rxDisplay=new TextView(this);root.addView(rxDisplay);
    details=new TextView(this);details.setPadding(0,12,0,12);root.addView(details);
    TextView info=new TextView(this);
    info.setText("Keep the app open for continuous tracking. Bluetooth, phone GPS and step sensor work without mobile data. Speech requires Android 12+ and installed on-device speech models. Phone microphone is used. The glasses + button works only if Android or RFCOMM exposes its event; use NEXT MODE if not.");
    root.addView(info);
    setupMediaButtons();
    askPermissions();
    refreshUi();
    ticker=new Runnable(){public void run(){if(!running)return;redraw(false);refreshUi();ui.postDelayed(this,2500);}};
    ui.postDelayed(ticker,900);
  }
  private Button add(LinearLayout root,String text,View.OnClickListener callback){
    Button b=new Button(this);b.setText(text);b.setAllCaps(false);b.setOnClickListener(callback);root.addView(b);return b;
  }
  private boolean granted(String p){return Build.VERSION.SDK_INT<23||checkSelfPermission(p)==PackageManager.PERMISSION_GRANTED;}
  private boolean btAllowed(){return Build.VERSION.SDK_INT<31||granted(Manifest.permission.BLUETOOTH_CONNECT);}
  private void askPermissions(){
    ArrayList<String> ask=new ArrayList<>();
    if(Build.VERSION.SDK_INT>=31&&!granted(Manifest.permission.BLUETOOTH_CONNECT))ask.add(Manifest.permission.BLUETOOTH_CONNECT);
    if(!granted(Manifest.permission.ACCESS_FINE_LOCATION))ask.add(Manifest.permission.ACCESS_FINE_LOCATION);
    if(!granted(Manifest.permission.RECORD_AUDIO))ask.add(Manifest.permission.RECORD_AUDIO);
    if(Build.VERSION.SDK_INT>=29&&!granted(Manifest.permission.ACTIVITY_RECOGNITION))ask.add(Manifest.permission.ACTIVITY_RECOGNITION);
    if(!ask.isEmpty())requestPermissions(ask.toArray(new String[0]),77);else{refresh();startSensorsAndGps();}
  }
  @Override public void onRequestPermissionsResult(int r,String[] ps,int[] rs){
    super.onRequestPermissionsResult(r,ps,rs);refresh();startSensorsAndGps();
  }
  private void showState(String s){stateMessage=s;refreshUi();}
  private void refreshUi(){
    if(status==null)return;
    status.setText((connected?"● CONNECTED":"○ NOT CONNECTED")+" | "+new String[]{"DASHBOARD","CAPTIONS","TRANSLATE"}[mode]+"\n"+stateMessage);
    rxDisplay.setText("Button diagnostic: "+lastIncoming+"\nLearned: "+(learnedSignature.isEmpty()?"none":learnedSignature));
    details.setText(String.format(Locale.US,"Steps: %s | Trip: %.2f mi\nGPS: %s | Speed: %.1f mph\nWeather: %s\n%s",
       steps<0?"sensor unavailable":""+steps,tripMeters/1609.344,
       gps?String.format(Locale.US,"%.5f, %.5f",latitude,longitude):"acquiring satellites",
       speedMps*2.2369363,weather.isEmpty()?"offline; no reading":weather,weatherLabel));
  }
  private void refresh(){
    if(!btAllowed()){showState("Allow Nearby devices first");return;}
    if(adapter==null||!adapter.isEnabled()){showState("Enable Bluetooth in phone Settings");return;}
    devices.clear();ArrayList<String> labels=new ArrayList<>();int selected=0;
    try{
      for(BluetoothDevice d:adapter.getBondedDevices()){
        String name=d.getName()==null?"Unnamed":d.getName();
        if(name.toLowerCase(Locale.US).contains("solos"))selected=devices.size();
        devices.add(d);labels.add(name+" — "+d.getAddress());
      }
    }catch(SecurityException e){showState("Bluetooth permission missing");return;}
    if(labels.isEmpty())labels.add("No paired devices — pair in Android Settings");
    ArrayAdapter<String> a=new ArrayAdapter<>(this,android.R.layout.simple_spinner_item,labels);
    a.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);paired.setAdapter(a);paired.setSelection(selected);
  }
  private void connect(){
    if(!btAllowed()){showState("Bluetooth permission required");return;}
    int index=paired.getSelectedItemPosition();
    if(index<0||index>=devices.size()){showState("Pair glasses in Settings first");return;}
    BluetoothDevice d=devices.get(index);showState("Connecting over RFCOMM...");
    worker.execute(()->{
      try{
        if(socket!=null)try{socket.close();}catch(Exception ignored){}
        socket=d.createRfcommSocketToServiceRecord(UUID.fromString("000011A0-0000-1000-8000-00805F9B34FB"));
        try{socket.connect();}
        catch(Exception first){
          try{socket.close();}catch(Exception ignored){}
          java.lang.reflect.Method m=d.getClass().getMethod("createRfcommSocket",int.class);
          socket=(BluetoothSocket)m.invoke(d,1);
          socket.connect();
        }
        output=socket.getOutputStream(); connected=true;
        ui.post(()->{showState("Connected. Sending offline dashboard");switchMode(0);});
        startIncoming(socket);
      }catch(Exception e){connected=false;ui.post(()->showState("Bluetooth connection failed: "+e.getMessage()));}
    });
  }
  private void startIncoming(BluetoothSocket connectedSocket){
    new Thread(()->{
      try{
        InputStream in=connectedSocket.getInputStream();byte[] b=new byte[2048];
        while(running&&connectedSocket.isConnected()){
          int n=in.read(b);if(n<=0)break;
          final byte[] packet=Arrays.copyOf(b,n);
          ui.post(()->receive(packet));
        }
      }catch(Exception ignored){}
      if(connectedSocket==socket&&running){connected=false;ui.post(()->showState("Disconnected: reconnect when ready"));}
    },"solos-input").start();
  }
  private static String hex(byte[] p,int len){
    StringBuilder s=new StringBuilder();for(int i=0;i<Math.min(len,p.length);i++)s.append(String.format(Locale.US,"%02X",p[i]&255));
    return s.toString();
  }
  private void receive(byte[] p){
    String signature=hex(p,Math.min(8,p.length));
    String shortRx=hex(p,Math.min(22,p.length));
    lastIncoming="RX "+p.length+" bytes: "+shortRx;
    long now=SystemClock.elapsedRealtime();
    // Ignore ordinary display ACKs shortly after we sent a frame.
    if(now-lastSendAt>1200&&now<learningUntil&&learnedSignature.isEmpty()){
      learnedSignature=signature;
      prefs.edit().putString("button_signature",learnedSignature).apply();
      learningUntil=0;showState("Candidate glasses button captured! Press it again to test.");
    }else if(now-lastSendAt>1200&&signature.equals(learnedSignature)&&!learnedSignature.isEmpty()){
      nextMode("Learned glasses button");
    }
    refreshUi();
  }
  private void setupMediaButtons(){
    try{
      mediaSession=new MediaSession(this,"Solos HUD Button");
      mediaSession.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS|MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS);
      mediaSession.setPlaybackState(new PlaybackState.Builder()
        .setActions(PlaybackState.ACTION_PLAY_PAUSE|PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_PLAY)
        .setState(PlaybackState.STATE_PLAYING,0,1).build());
      mediaSession.setCallback(new MediaSession.Callback(){
        @Override public boolean onMediaButtonEvent(Intent intent){
          KeyEvent event=intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
          if(event!=null&&event.getAction()==KeyEvent.ACTION_DOWN&&isModeKey(event.getKeyCode())){
            ui.post(()->nextMode("Bluetooth media button"));return true;
          }return super.onMediaButtonEvent(intent);
        }
        @Override public void onSkipToNext(){ui.post(()->nextMode("Media next"));}
        @Override public void onPlay(){ui.post(()->nextMode("Media play"));}
        @Override public void onPause(){ui.post(()->nextMode("Media pause"));}
      });
      mediaSession.setActive(true);
    }catch(Exception e){showState("Media buttons unavailable: "+e.getMessage());}
  }
  private boolean isModeKey(int key){
    return key==KeyEvent.KEYCODE_VOLUME_UP||key==KeyEvent.KEYCODE_MEDIA_NEXT||
      key==KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE||key==KeyEvent.KEYCODE_MEDIA_PLAY;
  }
  @Override public boolean dispatchKeyEvent(KeyEvent e){
    if(e.getAction()==KeyEvent.ACTION_DOWN&&e.getRepeatCount()==0&&isModeKey(e.getKeyCode())){
      nextMode("Android hardware key");return true;
    }
    return super.dispatchKeyEvent(e);
  }
  private void nextMode(String source){
    long now=SystemClock.elapsedRealtime();if(now-lastButtonAt<600)return;lastButtonAt=now;
    switchMode((mode+1)%3);lastIncoming=source+" • mode changed";refreshUi();
  }
  private void switchMode(int newMode){
    if(mode!=newMode)stopSpeech();
    mode=newMode;caption="";showState(new String[]{"Live dashboard","English offline captions","Spanish > English offline translation"}[mode]);
    if(mode>0)startSpeech();
    redraw(true);
  }
  private void startSensorsAndGps(){
    if(!sensorRegistered&&(Build.VERSION.SDK_INT<29||granted(Manifest.permission.ACTIVITY_RECOGNITION))){
      Sensor s=sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER);
      if(s==null)s=sensors.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR);
      if(s!=null){sensors.registerListener(this,s,SensorManager.SENSOR_DELAY_NORMAL);sensorRegistered=true;}
    }
    if(!gpsRegistered&&granted(Manifest.permission.ACCESS_FINE_LOCATION)){
      try{
        location.requestLocationUpdates(LocationManager.GPS_PROVIDER,3000,2,this);
        gpsRegistered=true;
      }catch(Exception e){showState("Enable location/GPS in Android settings");}
    }
  }
  @Override public void onSensorChanged(SensorEvent e){
    String today=new SimpleDateFormat("yyyyMMdd",Locale.US).format(new Date());
    if(e.sensor.getType()==Sensor.TYPE_STEP_COUNTER){
      int raw=(int)e.values[0];
      if(!today.equals(prefs.getString("step_day",""))||raw<prefs.getInt("step_base",0)){
        stepBase=raw;steps=0;prefs.edit().putString("step_day",today).putInt("step_base",raw).apply();
      }else{
        stepBase=prefs.getInt("step_base",raw);
        steps=Math.max(0,raw-stepBase);
      }
    }else if(e.sensor.getType()==Sensor.TYPE_STEP_DETECTOR){
      if(!today.equals(prefs.getString("step_day",""))){
        steps=0;prefs.edit().putString("step_day",today).putInt("detected_steps",0).apply();
      }else steps=prefs.getInt("detected_steps",0);
      steps++;
      prefs.edit().putInt("detected_steps",steps).apply();
    }
    redraw(false);
  }
  @Override public void onAccuracyChanged(Sensor sensor,int accuracy){}
  @Override public void onLocationChanged(Location l){
    if(l.hasAccuracy()&&l.getAccuracy()>75)return;
    gps=true;latitude=l.getLatitude();longitude=l.getLongitude();
    speedMps=l.hasSpeed()?Math.max(0,l.getSpeed()):0;
    if(previousFix!=null){
      float d=previousFix.distanceTo(l);
      long dt=l.getElapsedRealtimeNanos()-previousFix.getElapsedRealtimeNanos();
      double secs=dt/1e9;
      if(secs>0&&d>=3&&d<150&&d/secs<16)tripMeters+=d;
    }
    previousFix=l;
    redraw(false);
  }
  private void saveWeather(){
    String t=tempEntry.getText().toString().trim(),c=conditionEntry.getText().toString().trim();
    weather=(t+" "+c).trim();
    weatherLabel="MANUAL READING saved "+new SimpleDateFormat("MMM d h:mm a",Locale.US).format(new Date())+" • not live";
    prefs.edit().putString("weather",weather).putString("weather_temp",t)
      .putString("weather_condition",c).putString("weather_label",weatherLabel).apply();
    showState("Saved offline weather note");redraw(true);
  }
  private Intent speechIntent(String language){
    Intent i=new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
    i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
    i.putExtra(RecognizerIntent.EXTRA_LANGUAGE,language);
    i.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS,true);
    i.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE,true);
    i.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS,1);
    return i;
  }
  private void prepareSpeechPacks(){
    if(Build.VERSION.SDK_INT<33||!SpeechRecognizer.isOnDeviceRecognitionAvailable(this)){
      showState("Offline speech packs require supported Android 13+ device; for captions Android 12+");return;
    }
    stopSpeech();
    try{
      SpeechRecognizer setup=SpeechRecognizer.createOnDeviceSpeechRecognizer(this);
      setup.triggerModelDownload(speechIntent("en-US"));
      setup.triggerModelDownload(speechIntent("es-ES"));
      ui.postDelayed(setup::destroy,2500);
      showState("Asked Android to prepare English + Spanish speech packs. Accept any model download prompt on Wi-Fi once.");
    }catch(Exception ex){showState("Speech setup failed: "+ex.getMessage());}
  }
  private void downloadTranslationModel(){
    showState("Preparing Spanish/English model. Wi-Fi may be needed once.");
    if(translator==null){
      TranslatorOptions opt=new TranslatorOptions.Builder()
        .setSourceLanguage(TranslateLanguage.SPANISH)
        .setTargetLanguage(TranslateLanguage.ENGLISH).build();
      translator=Translation.getClient(opt);
    }
    translator.downloadModelIfNeeded(new DownloadConditions.Builder().requireWifi().build())
      .addOnSuccessListener(a->showState("Spanish > English translation downloaded. Now works without internet."))
      .addOnFailureListener(e->showState("Download failed; connect Wi-Fi and retry: "+e.getMessage()));
  }
  private void startSpeech(){
    if(mode==0)return;
    if(Build.VERSION.SDK_INT<31){showState("Offline voice captions require Android 12 or later");caption="Offline speech unavailable";redraw(true);return;}
    if(!granted(Manifest.permission.RECORD_AUDIO)){showState("Allow microphone permission for captions");return;}
    if(!SpeechRecognizer.isOnDeviceRecognitionAvailable(this)){
      caption="No offline speech engine on this phone";
      showState("Install Android's on-device speech recognition packs before using captions");redraw(true);return;
    }
    voiceWanted=true;
    try{
      recognizer=SpeechRecognizer.createOnDeviceSpeechRecognizer(this);
      recognizer.setRecognitionListener(new RecognitionListener(){
        @Override public void onReadyForSpeech(Bundle params){}
        @Override public void onBeginningOfSpeech(){}
        @Override public void onRmsChanged(float rms){}
        @Override public void onBufferReceived(byte[] buf){}
        @Override public void onEndOfSpeech(){}
        @Override public void onError(int error){
          if(!voiceWanted)return;
          if(error==SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED||error==SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE){
            caption="Speech language pack missing. Run PREPARE OFFLINE SPEECH PACKS.";
            voiceWanted=false;showState(caption);redraw(true);return;
          }
          if(error==SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS){voiceWanted=false;showState("Microphone permission denied");return;}
          restartListening();
        }
        @Override public void onResults(Bundle results){
          ArrayList<String> s=results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
          if(s!=null&&!s.isEmpty())hear(s.get(0),true);
          restartListening();
        }
        @Override public void onPartialResults(Bundle results){
          ArrayList<String> s=results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
          if(s!=null&&!s.isEmpty())hear(s.get(0),false);
        }
        @Override public void onEvent(int type,Bundle params){}
      });
      recognizer.startListening(speechIntent(mode==1?"en-US":"es-ES"));
      showState("On-device phone microphone listening");
    }catch(Exception ex){voiceWanted=false;showState("Offline microphone error: "+ex.getMessage());}
  }
  private void restartListening(){
    if(!voiceWanted||recognizer==null||mode==0)return;
    ui.postDelayed(()->{if(voiceWanted&&recognizer!=null)try{
      recognizer.startListening(speechIntent(mode==1?"en-US":"es-ES"));
    }catch(Exception e){showState("Speech restart: "+e.getMessage());}},700);
  }
  private void hear(String speech,boolean finalResult){
    if(mode==1){caption=speech;redraw(true);return;}
    if(mode!=2)return;
    caption=finalResult?"Translating: "+speech:speech;redraw(true);
    if(!finalResult)return;
    if(translator==null){
      caption="Download translation pack first";showState("Press DOWNLOAD SPANISH-ENGLISH MODEL on Wi-Fi once");redraw(true);return;
    }
    translator.translate(speech)
      .addOnSuccessListener(s->{if(mode==2){caption=s;redraw(true);}})
      .addOnFailureListener(e->{caption="Offline translation unavailable - download model first";showState(e.getMessage());redraw(true);});
  }
  private void stopSpeech(){
    voiceWanted=false;
    if(recognizer!=null){try{recognizer.cancel();recognizer.destroy();}catch(Exception ignored){}recognizer=null;}
  }
  private void redraw(boolean immediate){
    if(!connected||output==null)return;
    long now=SystemClock.elapsedRealtime();
    if(!immediate&&now-lastFrameAt<1600)return;
    lastFrameAt=now;
    int m=mode,n=steps;double dist=tripMeters,sp=speedMps,lat=latitude,lon=longitude;
    boolean g=gps;String cap=caption,w=weather.isEmpty()?"NO OFFLINE WEATHER DATA":weather;
    String source=weatherLabel,msg=voiceWanted?"ON-DEVICE SPEECH":"OFFLINE SPEECH UNAVAILABLE";
    worker.execute(()->{
      try{
        Bitmap bitmap=HudRenderer.render(m,cap,n,dist,sp,lat,lon,g,w,source,msg);
        byte[] data=makeFrame(bitmap);bitmap.recycle();
        ByteArrayOutputStream wake=new ByteArrayOutputStream();
        le(wake,0x601d,2);le(wake,4,2);le(wake,0,2);le(wake,0,4);
        if(!connected||output==null)return;
        output.write(wake.toByteArray());
        for(int x=0;x<data.length;x+=450)output.write(data,x,Math.min(450,data.length-x));
        output.flush();lastSendAt=SystemClock.elapsedRealtime();
      }catch(Exception ex){connected=false;ui.post(()->showState("Send failed: "+ex.getMessage()));}
    });
  }
  static void le(ByteArrayOutputStream out,int n,int bytes){for(int i=0;i<bytes;i++)out.write((n>>(i*8))&255);}
  static byte[] makeFrame(Bitmap bmp){
    int width=bmp.getWidth(),height=bmp.getHeight();int[] p=new int[width*height];bmp.getPixels(p,0,width,0,0,width,height);
    ByteArrayOutputStream r=new ByteArrayOutputStream();int last=0,count=0;
    for(int v:p){
      int rgb=((((v>>16)&255)>>3)<<11)|((((v>>8)&255)>>2)<<5)|((v&255)>>3);
      if(count>0&&(rgb!=last||count==255)){r.write(count);le(r,last,2);count=0;}
      last=rgb;count++;
    }
    if(count>0){r.write(count);le(r,last,2);}
    byte[] raw=r.toByteArray();ByteArrayOutputStream out=new ByteArrayOutputStream();
    le(out,0x601d,2);le(out,5,2);le(out,0,2);
    // Preserve original known-working v1 frame length framing for old Solos firmware.
    le(out,raw.length,4);
    out.write(2);out.write(0);le(out,0,2);le(out,1,2);le(out,0,2);le(out,0,2);
    le(out,width,2);le(out,height,2);out.write(raw,0,raw.length);
    return out.toByteArray();
  }
  @Override public void onDestroy(){
    running=false;connected=false;ui.removeCallbacksAndMessages(null);stopSpeech();
    if(sensorRegistered)sensors.unregisterListener(this);
    if(gpsRegistered)location.removeUpdates(this);
    if(mediaSession!=null)mediaSession.release();
    if(translator!=null)translator.close();
    worker.execute(()->{try{if(socket!=null)socket.close();}catch(Exception ignored){}});
    worker.shutdown();
    super.onDestroy();
  }
}
