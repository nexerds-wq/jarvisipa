package com.solos.legacyhud;
import android.Manifest;
import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.bluetooth.*;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.util.*;

public class MainActivity extends Activity {
  BluetoothAdapter bt;
  BluetoothSocket socket;
  OutputStream output;
  Spinner list;
  TextView status;
  EditText value;
  final java.util.ArrayList<BluetoothDevice> devices = new java.util.ArrayList<>();
  void state(String s) {runOnUiThread(() -> status.setText(s));}
  Button add(LinearLayout layout, String text, View.OnClickListener action) {
    Button b = new Button(this); b.setText(text); b.setOnClickListener(action); layout.addView(b); return b;
  }
  @Override public void onCreate(Bundle b) {
    super.onCreate(b); bt = BluetoothAdapter.getDefaultAdapter();
    ScrollView sc = new ScrollView(this);
    LinearLayout root = new LinearLayout(this); root.setPadding(22,22,22,22); root.setOrientation(1);
    sc.addView(root); setContentView(sc);
    TextView title = new TextView(this); title.setText("SOLOS LEGACY HUD\n2018 display glasses • RFCOMM"); title.setTextSize(22); root.addView(title);
    status = new TextView(this); status.setText("Pair Solos in Bluetooth settings first"); root.addView(status);
    list = new Spinner(this); root.addView(list);
    add(root,"Refresh paired devices",v -> refresh());
    add(root,"CONNECT",v -> connect());
    add(root,"TEST HUD — HELLO",v -> send("HELLO"));
    value = new EditText(this); value.setSingleLine(true); value.setText("HELLO FROM ANDROID"); root.addView(value);
    add(root,"SEND MY TEXT",v -> send(value.getText().toString()));
    add(root,"CLEAR",v -> send(""));
    if (Build.VERSION.SDK_INT >= 31 && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED)
      requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT},100);
    else refresh();
  }
  boolean allowed() {return Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;}
  @Override public void onRequestPermissionsResult(int rc,String[] ps,int[] rs){super.onRequestPermissionsResult(rc,ps,rs);if(allowed())refresh();}
  void refresh() {
    if(!allowed()){state("Allow Nearby Devices permission");return;}
    if(bt==null||!bt.isEnabled()){state("Turn Bluetooth on first");return;}
    devices.clear(); ArrayList<String> names=new ArrayList<>();int chosen=0;
    for(BluetoothDevice d:bt.getBondedDevices()){
      String name=d.getName();if(name==null)name="Unnamed";
      if(name.toLowerCase(java.util.Locale.US).contains("solos"))chosen=devices.size();
      devices.add(d);names.add(name+" • "+d.getAddress());
    }
    if(names.isEmpty())names.add("Pair glasses in Bluetooth Settings");
    ArrayAdapter<String> a=new ArrayAdapter<>(this,android.R.layout.simple_spinner_item,names);
    a.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);list.setAdapter(a);list.setSelection(chosen);
    state("Choose Solos and press CONNECT");
  }
  void connect() {
    if(!allowed()){state("Need Nearby Devices permission");return;}
    int i=list.getSelectedItemPosition();if(i<0||i>=devices.size()){state("Pair glasses first");return;}
    BluetoothDevice device=devices.get(i);state("Connecting...");
    new Thread(() -> {
      try {
        if(socket!=null)socket.close();
        socket=device.createRfcommSocketToServiceRecord(UUID.fromString("000011A0-0000-1000-8000-00805F9B34FB"));
        try {socket.connect();}
        catch(Exception first){
          try{socket.close();}catch(Exception ignored){}
          try {java.lang.reflect.Method m=device.getClass().getMethod("createRfcommSocket",int.class);socket=(BluetoothSocket)m.invoke(device,1);socket.connect();}
          catch(Exception second){throw new IOException("RFCOMM failed: "+first.getMessage()+" / "+second.getMessage());}
        }
        output=socket.getOutputStream();state("CONNECTED — press TEST HUD");
      }catch(Exception e){state("Connect failed: "+e.getMessage());}
    }).start();
  }
  static void le(ByteArrayOutputStream o,int n,int bytes){for(int i=0;i<bytes;i++)o.write((n>>(i*8))&255);}
  static byte[] frame(String message){
    Bitmap bmp=Bitmap.createBitmap(428,240,Bitmap.Config.ARGB_8888);
    Canvas c=new Canvas(bmp);c.drawColor(Color.BLACK);
    Paint p=new Paint(3);p.setTextAlign(Paint.Align.CENTER);p.setTypeface(Typeface.DEFAULT_BOLD);p.setColor(Color.WHITE);p.setTextSize(56);
    while(p.measureText(message)>405&&p.getTextSize()>14)p.setTextSize(p.getTextSize()-2);
    c.drawText(message,214,124,p);p.setTextSize(18);p.setColor(Color.GREEN);c.drawText("SOLOS LEGACY HUD",214,200,p);
    int[] px=new int[428*240];bmp.getPixels(px,0,428,0,0,428,240);
    ByteArrayOutputStream r=new ByteArrayOutputStream();int run=0,prev=0;
    for(int v:px){
      int rgb=((((v>>16)&255)>>3)<<11)|((((v>>8)&255)>>2)<<5)|((v&255)>>3);
      if(run>0&&(rgb!=prev||run==255)){r.write(run);le(r,prev,2);run=0;}
      prev=rgb;run++;
    }
    if(run>0){r.write(run);le(r,prev,2);}
    byte[] raw=r.toByteArray();ByteArrayOutputStream out=new ByteArrayOutputStream();
    le(out,0x601d,2);le(out,5,2);le(out,0,2);le(out,raw.length,4);
    out.write(2);out.write(0);le(out,0,2);le(out,1,2);le(out,0,2);le(out,0,2);le(out,428,2);le(out,240,2);
    out.write(raw,0,raw.length);return out.toByteArray();
  }
  void send(String message){
    if(output==null){state("Connect first");return;}state("Sending...");
    new Thread(() -> {try{
      ByteArrayOutputStream wake=new ByteArrayOutputStream();
      le(wake,0x601d,2);le(wake,4,2);le(wake,0,2);le(wake,0,4);
      output.write(wake.toByteArray());output.flush();Thread.sleep(100);
      byte[] image=frame(message);for(int n=0;n<image.length;n+=450)output.write(image,n,Math.min(450,image.length-n));
      output.flush();state("Sent "+image.length+" bytes — check lens");
    }catch(Exception e){state("Send failed: "+e.getMessage());}}).start();
  }
  @Override public void onDestroy(){try{if(socket!=null)socket.close();}catch(Exception ignored){}super.onDestroy();}
}
