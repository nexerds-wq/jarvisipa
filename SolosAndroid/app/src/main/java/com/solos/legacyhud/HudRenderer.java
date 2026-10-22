package com.solos.legacyhud;

import android.graphics.*;
import java.text.SimpleDateFormat;
import java.util.*;

public class HudRenderer {
  public static Bitmap render(int mode, String speech, int steps, double meters, double speedMps,
                              double lat, double lon, boolean gps, String weather,
                              String weatherSource, String note) {
    Bitmap bmp=Bitmap.createBitmap(428,240,Bitmap.Config.ARGB_8888);
    Canvas c=new Canvas(bmp); c.drawColor(Color.BLACK);
    Paint p=new Paint(3);
    int mint=Color.rgb(88,250,190), white=Color.WHITE, dim=Color.rgb(135,166,164), amber=Color.rgb(245,189,70);
    rect(c,p,0,0,428,4,mint);
    txt(c,p,"SOLOS  /  "+(mode==0?"OFFLINE DASHBOARD":mode==1?"LIVE CAPTIONS":"ES > EN TRANSLATOR"),16,24,17,mint,true);
    String date=new SimpleDateFormat("EEE, MMM d",Locale.US).format(new Date());
    String time=new SimpleDateFormat("h:mm a",Locale.US).format(new Date());
    txt(c,p,time,16,76,45,white,true);
    txt(c,p,date,18,99,18,dim,false);
    if(mode==0){
      txt(c,p,"STEPS",17,123,13,dim,false);
      txt(c,p,"TRIP",170,123,13,dim,false);
      txt(c,p,"SPEED",318,123,13,dim,false);
      txt(c,p,steps<0?"N/A":String.format(Locale.US,"%,d",steps),17,158,28,mint,true);
      txt(c,p,String.format(Locale.US,"%.2f mi",meters/1609.344),170,158,26,white,true);
      txt(c,p,String.format(Locale.US,"%.1f mph",speedMps*2.2369363),318,158,21,white,true);
      line(c,p,17,169,411,169,dim);
      txt(c,p,gps?String.format(Locale.US,"GPS %.5f, %.5f",lat,lon):"GPS: searching for satellites",16,192,17,gps?mint:amber,false);
      txt(c,p,"WEATHER: "+trim(weather,34),16,211,16,white,false);
      txt(c,p,trim(weatherSource,48),16,230,12,dim,false);
    }else {
      line(c,p,16,111,411,111,dim);
      txt(c,p,mode==1?"HEARING ENGLISH":"HEARING SPANISH > ENGLISH",16,132,15,dim,false);
      String s=(speech==null||speech.trim().isEmpty())?"Listening...":speech.trim();
      drawWrapped(c,p,s,16,164,392,23,25,white,3);
      txt(c,p,trim(note,55),16,229,13,mint,false);
    }
    return bmp;
  }
  static void rect(Canvas c,Paint p,int x,int y,int w,int h,int color){p.setColor(color);p.setStyle(Paint.Style.FILL);c.drawRect(x,y,x+w,y+h,p);}
  static void txt(Canvas c,Paint p,String s,float x,float y,float size,int color,boolean bold){
    p.setStyle(Paint.Style.FILL);p.setColor(color);p.setTextSize(size);
    p.setTypeface(bold?Typeface.create("sans-serif-condensed",Typeface.BOLD):Typeface.create("sans-serif",Typeface.NORMAL));
    c.drawText(s,x,y,p);
  }
  static void line(Canvas c,Paint p,int x,int y,int x2,int y2,int color){p.setColor(color);p.setStrokeWidth(1);c.drawLine(x,y,x2,y2,p);}
  static String trim(String x,int max){if(x==null)return "";return x.length()>max?x.substring(0,max-1)+"…":x;}
  static void drawWrapped(Canvas c,Paint p,String s,int x,int y,int width,int lineHeight,int size,int color,int maxLines){
    p.setTextSize(size);p.setTypeface(Typeface.DEFAULT_BOLD);p.setColor(color);
    String[] words=s.replace("\n"," ").split("\\s+");
    StringBuilder line=new StringBuilder(); int drawn=0;
    for(String word:words){
      String maybe=line.length()==0?word:line+" "+word;
      if(p.measureText(maybe)>width && line.length()>0){
        c.drawText(line.toString(),x,y+drawn*lineHeight,p);drawn++;line=new StringBuilder(word);
        if(drawn>=maxLines)return;
      }else line=new StringBuilder(maybe);
      while(p.measureText(line.toString())>width && line.length()>1){
        c.drawText(line.substring(0,line.length()-1),x,y+drawn*lineHeight,p);drawn++;
        line=new StringBuilder(line.substring(line.length()-1));
        if(drawn>=maxLines)return;
      }
    }
    if(drawn<maxLines)c.drawText(line.toString(),x,y+drawn*lineHeight,p);
  }
}
