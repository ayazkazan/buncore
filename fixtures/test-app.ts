const heap: any[] = [];

const server = Bun.serve({
  port: Number(process.env.PORT || 3388),
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/health") {
      return Response.json({
        ok: true,
        pid: process.pid,
        uptime: process.uptime(),
        memory: process.memoryUsage(),
      });
    }

    if (url.pathname === "/cpu") {
      let sum = 0;
      for (let i = 0; i < 7_500_000; i++) sum += Math.sqrt(i) * Math.sin(i);
      return new Response(String(sum));
    }

    if (url.pathname === "/leak") {
      for (let i = 0; i < 25_000; i++) {
        heap.push({ i, payload: "x".repeat(128), ts: Date.now() });
      }
      return Response.json({ retained: heap.length });
    }

    return new Response(`buncore fixture pid=${process.pid}\n`);
  },
});

console.log(`fixture online http://127.0.0.1:${server.port} pid=${process.pid}`);
