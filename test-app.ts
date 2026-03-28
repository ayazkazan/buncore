// Test application for BPM
const server = Bun.serve({
  port: 3334,
  fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/health") {
      return new Response(JSON.stringify({
        status: "ok",
        memory: process.memoryUsage(),
        uptime: process.uptime(),
        pid: process.pid,
      }), { headers: { "Content-Type": "application/json" } });
    }

    if (url.pathname === "/leak") {
      // Simulate memory leak for testing
      const arr: any[] = [];
      for (let i = 0; i < 100000; i++) {
        arr.push({ data: "x".repeat(100), ts: Date.now() });
      }
      return new Response(`Allocated ${arr.length} objects`);
    }

    if (url.pathname === "/cpu") {
      // CPU intensive task
      let sum = 0;
      for (let i = 0; i < 10000000; i++) {
        sum += Math.sqrt(i) * Math.sin(i);
      }
      return new Response(`CPU result: ${sum}`);
    }

    return new Response(`Hello from BPM test app! PID: ${process.pid}\nUptime: ${process.uptime().toFixed(1)}s`);
  },
});

console.log(`Test server running on http://localhost:${server.port} (PID: ${process.pid})`);

// Periodic log output
setInterval(() => {
  const mem = process.memoryUsage();
  console.log(`[${new Date().toISOString()}] Memory: RSS=${(mem.rss/1024/1024).toFixed(1)}MB Heap=${(mem.heapUsed/1024/1024).toFixed(1)}MB/${(mem.heapTotal/1024/1024).toFixed(1)}MB`);
}, 5000);
