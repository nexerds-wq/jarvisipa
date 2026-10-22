package com.solos.legacyhud;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

public final class IphoneBridge {
  public interface Sender { boolean connected(); void display(String text); }
  private final Context context;
  private final Sender sender;
  private final ExecutorService threads=Executors.newCachedThreadPool();
  private volatile boolean open=false;
  private ServerSocket server;
  private int port=8765;
  public IphoneBridge(Context ctx,Sender listener){context=ctx;sender=listener;}
  public void start() throws IOException {
    server=new ServerSocket();server.setReuseAddress(true);server.bind(new InetSocketAddress("0.0.0.0",port));
    open=true;
    threads.execute(()->{
      while(open)try{
        Socket peer=server.accept();
        peer.setSoTimeout(5500);
        threads.execute(()->serve(peer));
      }catch(IOException ex){if(open)android.util.Log.e("SolosBridge","accept",ex);}
    });
  }
  public String addresses(){
    StringBuilder found=new StringBuilder();
    try{
      Enumeration<NetworkInterface> nics=NetworkInterface.getNetworkInterfaces();
      while(nics.hasMoreElements()){
        NetworkInterface nic=nics.nextElement();
        if(!nic.isUp()||nic.isLoopback())continue;
        Enumeration<InetAddress> addrs=nic.getInetAddresses();
        while(addrs.hasMoreElements()){
          InetAddress ip=addrs.nextElement();
          if(ip instanceof Inet4Address&&!ip.isLoopbackAddress()&&!ip.isLinkLocalAddress()){
            if(found.length()>0)found.append("\n");
            found.append("http://").append(ip.getHostAddress()).append(":").append(port);
          }
        }
      }
    }catch(Exception ignored){}
    return found.length()==0?"Turn on Android hotspot or connect both phones to same Wi-Fi.":found.toString();
  }
  private String line(InputStream in)throws IOException {
    ByteArrayOutputStream bytes=new ByteArrayOutputStream();int x;
    while((x=in.read())!=-1){
      if(x=='\n')break;
      if(x!='\r')bytes.write(x);
      if(bytes.size()>8192)throw new IOException("Too much header data");
    }
    return new String(bytes.toByteArray(),StandardCharsets.ISO_8859_1);
  }
  private void serve(Socket socket){
    try(Socket client=socket){
      InputStream in=new BufferedInputStream(client.getInputStream());
      String request=line(in);String[] parts=request.split(" ");
      if(parts.length<2){write(client,400,"text/plain","Bad Request");return;}
      String method=parts[0],route=parts[1];
      int size=0;String h;
      while(!(h=line(in)).isEmpty()){
        if(h.toLowerCase(Locale.US).startsWith("content-length:"))size=Integer.parseInt(h.substring(h.indexOf(':')+1).trim());
        if(size>8192){write(client,413,"text/plain","Message too long");return;}
      }
      if(method.equals("GET")&&(route.equals("/")||route.startsWith("/?"))){
        String html;
        try(InputStream asset=context.getAssets().open("iphone.html")){
          ByteArrayOutputStream out=new ByteArrayOutputStream();
          byte[] bytes=new byte[8192];int n;
          while((n=asset.read(bytes))!=-1)out.write(bytes,0,n);
          html=new String(out.toByteArray(),StandardCharsets.UTF_8);
        }
        write(client,200,"text/html; charset=utf-8",html);return;
      }
      if(route.startsWith("/status")){
        write(client,200,"application/json",sender.connected()?"{\"connected\":true}":"{\"connected\":false}");
        return;
      }
      String message="";
      if(method.equals("POST")&&route.equals("/send")){
        byte[] bytes=new byte[size];int n=0;
        while(n<size){int got=in.read(bytes,n,size-n);if(got<0)break;n+=got;}
        message=new String(bytes,0,n,StandardCharsets.UTF_8);
      }else if(method.equals("GET")&&route.startsWith("/send?text=")){
        message=URLDecoder.decode(route.substring("/send?text=".length()),"UTF-8");
      }else{write(client,404,"text/plain","Not Found");return;}
      if(!sender.connected()){write(client,503,"text/plain","Connect Solos glasses in the Android app first.");return;}
      message=message.replaceAll("[\\p{Cntrl}&&[^\\n]]"," ").trim();
      if(message.length()>700)message=message.substring(0,700);
      sender.display(message);
      write(client,202,"text/plain","Sent to Android Bluetooth transmitter");
    }catch(Exception ex){android.util.Log.w("SolosBridge","request",ex);}
  }
  private void write(Socket socket,int status,String type,String value)throws IOException{
    byte[] bytes=value.getBytes(StandardCharsets.UTF_8);
    String head="HTTP/1.1 "+status+" "+(status==200?"OK":status==202?"Accepted":"Error")+"\r\n"+
      "Content-Type: "+type+"\r\nContent-Length: "+bytes.length+"\r\nCache-Control: no-store\r\n"+
      "Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n";
    OutputStream out=socket.getOutputStream();
    out.write(head.getBytes(StandardCharsets.US_ASCII));
    out.write(bytes);out.flush();
  }
  public void stop(){
    open=false;try{if(server!=null)server.close();}catch(Exception ignored){}
    threads.shutdownNow();
  }
}
