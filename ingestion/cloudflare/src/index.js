// A separate scheduler can replace lost Actions cron delivery. The durable
// PostgreSQL runtime decides what is due; duplicate dispatches are harmless.
export async function reconcile(env, request = fetch, now = Date.now()) {
  if (!env.GITHUB_DISPATCH_TOKEN) throw new Error("Missing dispatch credential");
  const base = `https://api.github.com/repos/${env.GITHUB_REPOSITORY}/actions/workflows/${env.WORKFLOW}`;
  const headers = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${env.GITHUB_DISPATCH_TOKEN}`,
    "User-Agent": "fin-ingestion-watchdog",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  const response = await request(`${base}/runs?branch=main&per_page=10`, {headers});
  if (!response.ok) throw new Error(`Workflow status HTTP ${response.status}`);
  const runs = (await response.json()).workflow_runs;
  if (!Array.isArray(runs)) throw new Error("Invalid workflow status contract");
  if (runs.some(run => ["queued", "in_progress", "waiting", "pending", "requested"].includes(run.status))) {
    return {status: "ACTIVE"};
  }
  const last = runs.find(run => run.status === "completed");
  if (last && now - Date.parse(last.updated_at) < 10 * 60 * 1000) {
    return {status: "RECENT"};
  }
  const dispatch = await request(`${base}/dispatches`, {
    method: "POST", headers: {...headers, "Content-Type": "application/json"},
    body: JSON.stringify({ref: "main", inputs: {profile: "recover"}}),
  });
  if (dispatch.status !== 204) throw new Error(`Workflow dispatch HTTP ${dispatch.status}`);
  return {status: "DISPATCHED"};
}

export default {
  async scheduled(_controller, env, context) {
    context.waitUntil(reconcile(env).then(result => console.log(JSON.stringify(result))));
  },
  async fetch(request, env) {
    if (!env.HEALTH_TOKEN || request.headers.get("Authorization") !== `Bearer ${env.HEALTH_TOKEN}`) {
      return new Response("Unauthorized", {status: 401});
    }
    try {
      return Response.json(await reconcile(env));
    } catch {
      return Response.json({status: "FAILED"}, {status: 503});
    }
  },
};
