package com.solos.legacyhud;
public final class NativeJarvis {
  static {System.loadLibrary("jarvis_native");}
  public static native String load(String path);
  public static native String answer(String question);
  private NativeJarvis(){}
}
