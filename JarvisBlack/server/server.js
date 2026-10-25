"use strict";

const http = require("node:http");

const PORT = Number(process.env.PORT || 3000);
const CLIENT_TOKEN = process.env.JARVIS_CLIENT_TOKEN;
const API_KEY = process.env.OPENAI_API_KEY;
const MODEL = process.env.JARVIS_MODEL || "gpt-5.1";
const MOCK = process.env.JARVIS_MOCK === "1";
const requests = new Map();

function textFromResponse(data) {
  if (typeof data.output_text === "string") return data.output_text.trim();
  return (data.output || [])
    .flatMap((item) => item.content || [])
    .filter((item) => item.type === "output_text" && typeof item.text === "string")
    .map((item) => item.text)
    .join(" ")
    .trim();
}

function send(res, status, value) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  res.end(JSON.stringify(value));
}

function rateLimit(ip) {
  const now = Date.now();
  const attempts = (requests.get(ip) || []).filter((time) => now - time < 60_000);
  if (attempts.length >= 12) return false;
  attempts.push(now);
  requests.set(ip, attempts);
  return true;
}

async function postOpenAI(endpoint, body) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45_000);
  try {
    const response = await fetch(`https://api.openai.com/v1/${endpoint}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${API_KEY}` },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      // Deliberately do not expose account or API details to a phone client.
      throw new Error(`OpenAI ${endpoint} request failed: HTTP ${response.status}`);
    }
    return response;
  } finally {
    clearTimeout(timeout);
  }
}

async function speak(text) {
  if (MOCK) return null;
  const response = await postOpenAI("audio/speech", {
    model: "gpt-4o-mini-tts",
    voice: "marin",
    response_format: "mp3",
    instructions: "Speak naturally like a thoughtful, calm, capable assistant. Clear diction, moderate pace, conversational, not robotic.",
    input: text.slice(0, 1800),
  });
  const bytes = Buffer.from(await response.arrayBuffer());
  return bytes.toString("base64");
}

async function answer(message, history) {
  if (MOCK) return `I heard: ${message}`;
  const input = history.concat([{ role: "user", content: message }]);
  const response = await postOpenAI("responses", {
    model: MODEL,
    instructions: "You are Jarvis, a helpful voice-first personal assistant. Respond to natural conversation and ordinary questions clearly. Keep spoken answers concise, ideally one or two sentences, unless the user asks for detail. Never claim you controlled a phone app unless a real local command did it. If asked to play music, remind the user to say 'Hey Jarvis, play [song]' to use the phone's Apple Music support.",
    input,
    max_output_tokens: 350,
  });
  const text = textFromResponse(await response.json());
  if (!text) throw new Error("AI returned no spoken text");
  return text;
}

async function readJSON(req) {
  let body = "";
  for await (const chunk of req) {
    body += chunk.toString("utf8");
    if (body.length > 65536) throw new Error("Request too large");
  }
  return JSON.parse(body);
}

async function handler(req, res) {
  if (req.url === "/health" && req.method === "GET") {
    return send(res, 200, { ok: true });
  }
  const token = req.headers.authorization || "";
  if (token !== `Bearer ${CLIENT_TOKEN}`) return send(res, 401, { error: "Unauthorized" });
  if (!rateLimit(req.socket.remoteAddress || "unknown")) return send(res, 429, { error: "Slow down" });
  if (req.method !== "POST" || !["/chat", "/speak"].includes(req.url)) {
    return send(res, 404, { error: "Not found" });
  }

  try {
    const payload = await readJSON(req);
    if (req.url === "/speak") {
      const text = String(payload.text || "").slice(0, 1800);
      if (!text.trim()) return send(res, 400, { error: "Missing text" });
      return send(res, 200, { audioBase64: await speak(text) });
    }
    const message = String(payload.message || "").trim().slice(0, 4000);
    if (!message) return send(res, 400, { error: "Missing message" });
    const history = (Array.isArray(payload.history) ? payload.history : [])
      .slice(-12)
      .filter((line) => line && ["user", "assistant"].includes(line.role) && typeof line.content === "string")
      .map((line) => ({ role: line.role, content: line.content.slice(0, 2000) }));
    const reply = await answer(message, history);
    let audioBase64 = null;
    try { audioBase64 = await speak(reply); }
    catch (error) { console.error("TTS failed:", error.message); }
    return send(res, 200, { reply, audioBase64 });
  } catch (error) {
    console.error("Jarvis request failed:", error.message);
    return send(res, 500, { error: "AI service unavailable" });
  }
}

function createServer() {
  if (!CLIENT_TOKEN || CLIENT_TOKEN.length < 20) {
    throw new Error("Set JARVIS_CLIENT_TOKEN to a long random string");
  }
  if (!MOCK && !API_KEY) throw new Error("Set OPENAI_API_KEY on the server");
  return http.createServer((req, res) => {
    handler(req, res).catch((error) => {
      console.error(error);
      if (!res.headersSent) send(res, 500, { error: "Server error" });
    });
  });
}

if (require.main === module) {
  createServer().listen(PORT, "127.0.0.1", () => {
    console.log(`Jarvis voice service listening on 127.0.0.1:${PORT}`);
  });
}

module.exports = { textFromResponse, createServer, handler };
