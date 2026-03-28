console.log(`worker online pid=${process.pid}`);

setInterval(() => {
  console.log(`worker heartbeat pid=${process.pid} ts=${Date.now()}`);
}, 1500);

await new Promise(() => {});
