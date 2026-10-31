import {test} from "node:test";
import assert from "node:assert/strict";
import worker, {reconcile} from "../src/index.js";

const env = {GITHUB_DISPATCH_TOKEN: "test", GITHUB_REPOSITORY: "owner/repo", WORKFLOW: "engine-schedule.yml"};

test("lost delivery dispatches a bounded recovery rather than a source job", async () => {
  const calls = [];
  const request = async (url, options) => {
    calls.push({url, options});
    return calls.length === 1 ? Response.json({workflow_runs: []}) : new Response(null, {status: 204});
  };
  assert.equal((await reconcile(env, request)).status, "DISPATCHED");
  assert.equal(JSON.parse(calls[1].options.body).inputs.profile, "recover");
});

test("active executions do not cause a dispatch storm", async () => {
  let calls = 0;
  const request = async () => { calls++; return Response.json({workflow_runs: [{status: "in_progress"}]}); };
  assert.equal((await reconcile(env, request)).status, "ACTIVE");
  assert.equal(calls, 1);
});

test("a recent completed execution is allowed a quiet interval", async () => {
  const now = Date.now();
  const request = async () => Response.json({workflow_runs: [{status: "completed", updated_at: new Date(now).toISOString()}]});
  assert.equal((await reconcile(env, request, now)).status, "RECENT");
});

test("provider errors are visible and a public request cannot trigger jobs", async () => {
  await assert.rejects(reconcile(env, async () => new Response(null, {status: 403})), /HTTP 403/);
  assert.equal((await worker.fetch(new Request("https://example.test/"), env)).status, 401);
});
