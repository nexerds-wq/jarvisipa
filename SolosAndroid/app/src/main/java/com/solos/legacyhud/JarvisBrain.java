package com.solos.legacyhud;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
import org.vosk.*;
import org.vosk.android.*;
import java.io.*;
import java.util.Locale;
import java.util.concurrent.*;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class JarvisBrain implements org.vosk.android.RecognitionListener {
  public interface Listener {
    void onStatus(String status);
    void onAnswer(String answer);
  }
  private final Activity activity;
  private final Listener listener;
  private final Handler ui = new Handler(Looper.getMainLooper());
  private final ExecutorService tasks = Executors.newSingleThreadExecutor();
  private volatile boolean working=true,ready=false,speechReady=false,busy=false;
  private boolean awaitingQuestion=false;
  private volatile boolean wantListening=false;
  private volatile boolean initializing=false;
  private Model speechModel;
  private SpeechService speechService;
  private String lastAnswer="";

  public JarvisBrain(Activity activity,Listener callback){
    this.activity=activity;this.listener=callback;
  }
  private void status(String s){ui.post(()->{if(working)listener.onStatus(s);});}
  private void answer(String s){lastAnswer=s;ui.post(()->{if(working)listener.onAnswer(s);});}

  public void prepare(){
    if(initializing||ready)return;
    initializing=true;
    tasks.execute(()->{
      try {
        status("Preparing the small local AI model...");
        File modelFile=new File(activity.getFilesDir(),"jarvis.gguf");
        if(!modelFile.exists()||modelFile.length()<85000000)copyAsset("jarvis.gguf",modelFile);
        String reply=NativeJarvis.load(modelFile.getAbsolutePath());
        if(!"READY".equals(reply)){status(reply);return;}
        ready=true;
        status("Offline AI ready. Loading offline speech...");
        File speechDirectory=new File(activity.getFilesDir(),"vosk-english");
        File folder=new File(speechDirectory,"vosk-model-small-en-us-0.15");
        if(!new File(folder,"am").isDirectory()){
          extractSpeechModel(speechDirectory);
        }
        speechModel=new Model(folder.getAbsolutePath());
        speechReady=true;
        status("Offline Jarvis ready. Say HEY JARVIS + a question.");
        if(wantListening)ui.post(this::startListeningNow);
      }catch(Throwable t){status("Jarvis setup failed: "+t.getClass().getSimpleName()+" "+t.getMessage());}
      finally{initializing=false;}
    });
  }
  private void copyAsset(String name,File dest)throws IOException{
    File temp=new File(dest.getAbsolutePath()+".part");
    if(temp.exists())temp.delete();
    try(InputStream in=activity.getAssets().open(name);FileOutputStream out=new FileOutputStream(temp)){
      byte[] buf=new byte[65536];int n;
      while((n=in.read(buf))>=0){if(n>0)out.write(buf,0,n);}
      out.getFD().sync();
    }catch(Exception e){temp.delete();throw e;}
    if(!temp.renameTo(dest))throw new IOException("Cannot copy GGUF model to internal storage");
  }
  private void extractSpeechModel(File target)throws IOException{
    target.mkdirs();
    String base=target.getCanonicalPath()+File.separator;
    try(ZipInputStream zip=new ZipInputStream(activity.getAssets().open("vosk-en.zip"))){
      ZipEntry e;byte[] buf=new byte[32768];
      while((e=zip.getNextEntry())!=null){
        File dest=new File(target,e.getName());
        String canonical=dest.getCanonicalPath();
        if(!canonical.startsWith(base))throw new IOException("Invalid speech model path");
        if(e.isDirectory()){dest.mkdirs();continue;}
        File parent=dest.getParentFile();
        if(parent!=null)parent.mkdirs();
        try(FileOutputStream out=new FileOutputStream(dest)){
          int n;while((n=zip.read(buf))!=-1){if(n>0)out.write(buf,0,n);}
        }
        zip.closeEntry();
      }
    }
  }
  public void listen(){
    wantListening=true;prepare();
    if(speechReady)startListeningNow();
  }
  private void startListeningNow(){
    if(!working||!wantListening||!speechReady||speechService!=null)return;
    if(android.os.Build.VERSION.SDK_INT>=23 &&
       activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED){
      status("Allow Microphone in Android Settings, then press START VOICE.");
      return;
    }
    try{
      Recognizer rec=new Recognizer(speechModel,16000.0f);
      speechService=new SpeechService(rec,16000.0f);
      speechService.startListening(this);
      status("Listening locally. Say: Hey Jarvis, what is...");
    }catch(Exception e){status("Offline microphone failed: "+e.getMessage());}
  }
  public void stopListening(){
    wantListening=false;awaitingQuestion=false;
    if(speechService!=null){
      try{speechService.cancel();speechService.shutdown();}catch(Exception ignored){}
      speechService=null;
    }
  }
  public void ask(String question){
    if(!working)return;
    question=question==null?"":question.trim();
    if(question.isEmpty())return;
    if(!ready){status("AI model not ready yet.");prepare();return;}
    if(busy){status("Jarvis is still answering.");return;}
    busy=true;
    final String input=question;
    answer("YOU: "+input+"\n\nJARVIS IS THINKING...");
    status("Generating answer fully on this Android phone...");
    tasks.execute(()->{
      try{
        String response=NativeJarvis.answer(input);
        answer("JARVIS: "+response.trim());
        status("Answered offline. Say Hey Jarvis for another question.");
      }catch(Throwable t){
        answer("Jarvis error: "+t.getMessage());
        status("AI failed: "+t.getClass().getSimpleName());
      }finally{busy=false;}
    });
  }
  private static String read(String json,String field){
    try{return new JSONObject(json).optString(field,"").trim().toLowerCase(Locale.US);}
    catch(Exception e){return "";}
  }
  private void process(String phrase){
    if(!working||!wantListening||phrase.isEmpty())return;
    // Vosk can transcribe 'Jarvis' differently on weak microphones. Use on-screen ask as a fallback.
    if(phrase.contains("hey jarvis")||phrase.contains("hey service")||phrase.startsWith("jarvis")){
      awaitingQuestion=true;
      String after=phrase.replaceFirst("(?i)^.*?(hey jarvis|hey service|jarvis)[ ,]*","");
      if(after.isEmpty()){status("Jarvis listening: ask your question.");return;}
      awaitingQuestion=false;ask(after);return;
    }
    if(awaitingQuestion){
      awaitingQuestion=false;
      ask(phrase);
    }
  }
  @Override public void onResult(String data){process(read(data,"text"));}
  @Override public void onPartialResult(String data){}
  @Override public void onFinalResult(String data){process(read(data,"text"));}
  @Override public void onError(Exception e){status("Speech error: "+e.getMessage());}
  @Override public void onTimeout(){status("Voice timed out; press START VOICE.");}
  public void close(){
    working=false;stopListening();
    tasks.shutdownNow();
    if(speechModel!=null){speechModel.close();speechModel=null;}
  }
}
