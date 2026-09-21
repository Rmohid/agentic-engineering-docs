# Unattended Agent Operations: The Agent Nobody Is Watching Is Infrastructure, Not a Colleague

**Thesis:** An agent that runs on a schedule with nobody at the keyboard must be treated as production infrastructure — its permissions are granted per actor class, its progress lives in a durable ledger, its spending brake reads a counter that only moves one way, and an exhausted budget is a failure, never a finish.

**Prerequisites:** [Cost Engineering for LLM Systems](cost-engineering-for-llm-systems.md), [Quality Gates in Agentic Systems](quality-gates-in-agentic-systems.md), [Reliability Engineering for LLM Applications](reliability-engineering-for-llm-applications.md).

**Reading time:** 18 minutes.

Agent systems have three operational modes. Interactive: a human types, reads, and notices. Delegated: a human hands work to a subagent and reads the result in the same session. Unattended: a scheduler starts the process, nobody reads the transcript, and the only thing that can catch a problem is a mechanism that existed before the run started. Almost every failure below is someone carrying an interactive habit into a job that runs at 03:00 with nobody in the room.

| What teams assume | What actually happens |
|---|---|
| "The scheduled job and my interactive session use the same credentials; that is convenient." | A mechanical script and a reasoning agent are different actors with different blast radii; one shared credential set gives the reasoning actor the script actor's standing authority. The emerging industry position is that agents are first-class identities holding no standing privilege — see [CoSAI, Agentic Identity and Access Management](https://www.coalitionforsecureai.org/wp-content/uploads/2026/04/agentic-identity-and-access-control.pdf). |
| "The coordinating session can hold the list of what is done." | The session dies and takes the list with it. One fleet's sixteen dispatched workers were tracked only inside the parent session's context; when it ended at its call limit, the record of which workers had landed existed nowhere, and items were re-dispatched with zero context up to six times. |
| "We set a monthly spend cap, so spend is capped." | Provider caps are increasingly notification rather than cutoff ([OpenAI spend-limit behaviour rechecked July 2026](https://runcycles.io/blog/openai-api-budget-limits-per-user-per-run-per-tenant)), and an in-run brake is only as good as the counter it reads. A month-to-date usage field on one provider payload read `222.378901663` at run start and `72.487145487` thirty minutes later: a delta of `-149.89`. The stop condition `usage_now - usage_start >= allowance` could never fire. |
| "If the job stops running, we will notice." | Scheduled work fails by absence, and absence produces no error to monitor. A Kubernetes CronJob controller permanently stops scheduling a job after 100 missed start times and logs a single line — no event, no alert ([CronJobs silently fail more than you think](https://dev.to/krissv/kubernetes-cronjobs-silently-fail-more-than-you-think-2nb9)). |
| "Hitting the iteration limit ends the run cleanly." | A capped run ended reporting success while its work item stayed open and its commit sat unpushed; the runner could not distinguish "the user walked away" from "capped mid-work". Contrast the infrastructure that names the limit that killed it: a container killed by its own memory limit reports `OOMKilled` and exit code 137, not success ([Kubernetes pod failure reasons](https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/)). |
| "Two workers on one checkout is fine; git will sort it out." | Nothing refused the second writer. In one measured incident the reflog showed six rewrites in three minutes on one branch, one session's commit landing between another session's amend and its next commit. The loss is uncommitted work, and a single `reset` discards it. |
| "Waiting for a slow step means polling until it is ready." | A polling parent re-sent the same standing prompt every iteration until it hit a 500-call wall; seven of sixteen workers died at a 250-call wall and were re-dispatched with no prior context, burning roughly 1,750 calls plus a full re-derivation each time. |

## The Core Tension

Autonomy is bought with reach, and reach without a witness is where loss happens. To finish work nobody is steering, an agent must run commands, write files, spend money, and open outbound connections. Each is also a way to lose something permanently: a database volume and its mounted backups were destroyed in one API call by a coding agent that believed it was working in staging ([The Register, April 2026](https://www.theregister.com/software/2026/04/27/cursor-opus-agent-snuffs-out-startups-production-database/5224442)). The unattended case removes the last compensating control — the human who would have asked why a volume was being deleted.

The naive response is to add supervision: dashboards, more alerts, a human reviewing logs each morning. This fails twice over. The reviewer is doing the work the automation was supposed to remove, and the review happens after the irreversible act. The response that scales is structural: move each decision out of the model's judgment into a mechanism that holds whatever the model does. An exit code holds. A lock file holds. A cap read from a counter that only moves one way holds. A prompt saying "never spend more than five dollars" does not, because the thing reading it is the same nondeterministic process you are trying to bound.

A second pressure runs the other way, and practitioners underestimate it. Supervision machinery can make an unattended fleet cost more than the work it watches. Measured: a fleet of scheduled jobs ran 353 sessions and 15,826 model calls in seven days, and three watcher jobs alone (at 15-minute, 30-minute, and hourly intervals) produced more than 120 runs in that window, most of them no-change ticks, several burning 100 to 240 calls each. In the same week, roughly a quarter of the operator's interactive volume was hand-run fleet forensics — a human re-doing by hand what a changed-output watchdog should have surfaced.

The tension is therefore not autonomy versus safety, but autonomy bounded by structure versus autonomy bounded by attention — and the second fails at both ends.

## Failure Taxonomy

**1. Shared authority across actor classes.** A mechanical job that calls no model and a reasoning agent that reads untrusted content are different actors: the script fails deterministically and loudly, the agent fails creatively and can be steered by what it reads. Granting both one credential set, one write reach, and one outbound permission bounds the agent's worst case by the script's blast radius, not its own. No boundary existed between the classes, so no boundary could be tested. The published direction is unambiguous: eliminate standing privilege, grant access just-in-time scoped to the task, revoke it on completion ([Resilient Cyber on CoSAI's imperatives](https://www.resilientcyber.io/p/identity-is-the-agentic-ai-problem)).

**2. Coordination state held in a live session.** A parent that tracks its children in its own context — dispatched, landed, failed — holds the only copy of that state in the one place guaranteed to evaporate. When the parent ends, by user action or at its call cap, the state is gone and the work is unaccounted for. The signature is re-dispatch: the same item handed out again with no memory of the previous attempt, re-deriving the whole search space. On one fleet the same item was dispatched six or more times. The deeper problem is not the wasted calls; a run that ends this way cannot report what it did.

**3. A brake on a non-monotonic counter.** Every in-run spending brake has the shape "if the quantity spent since the run began has reached the allowance, stop", and that shape is correct only if the quantity never decreases over the period measured. On the run in the myth table, two fields on one provider payload disagreed: month-to-date usage fell by 149.89 while remaining credit on the same response fell by 0.109. The usage field was a windowed counter that could roll; remaining credit only falls. Because the stop condition subtracted the rolling counter, its result was negative from the first re-read and the brake was dead — not weakened, not noisy, dead — while appearing installed. A brake that cannot fire is worse than no brake, because it is recorded as an installed control and nobody builds the second one.

**4. Silent non-firing.** A job that fails loudly is a manageable incident; a job that stops firing is invisible, because scheduled work produces no traffic and no error when it does not start. The causes are mundane: a scheduler in a crash loop, a job suspended by a rollout, a schedule change that leaves a weekend gap, a fire hand-off that fails so the run never begins and no execution record is written at all. The tell-tale shape is a job that works every time it is triggered manually and never auto-fires.

**5. A resource limit reported as success.** When a run ends because it consumed its budget, its call cap, or its wall-clock limit, three things must be true and usually only one is: the limit is recorded in machine-readable form, the status is a failure, and the work is left in a state a successor can pick up. The measured failure had none of the three. The cap arrived as a synthetic request for a text-only summary, the model complied with a sentence saying it still needed to commit, the process closed with the ordinary end reason it uses when a user walks away, and the fleet's watchdogs — which key on that end reason — saw nothing wrong. Meanwhile the work item stayed open and the commit sat unpushed on an agent branch with no remote ref.

**6. The second writer.** Two processes writing one working copy do not conflict in a way anyone sees. Version control detects the landing collision — a push that is not fast-forward is refused — but not the interleaving before the landing. Measured: two live sessions wrote one working copy and one branch; the reflog showed six rewrites in three minutes. Neither was notified, and either one's reset could have discarded the other's uncommitted work. That is the loss class: committed work is recoverable from history, pushed work from the remote, and the contents of a working tree from nowhere.

**7. The polling burn and the unbounded re-dispatch.** Polling converts waiting into metered activity, and in an agent system the unit is a full model turn, so a poll loop resends the session's whole context every iteration. A parent that spends eight minutes waiting in a poll loop has spent its allowance waiting, not working. The second half is re-dispatch: when a capped child is retried by a parent with no memory of the child's progress, the child's whole search space is re-derived, with no natural limit on repetitions. Seven of sixteen workers died at the same call wall in one fleet, and the parent re-dispatched them without context.

**8. The unkeyed obligation set.** A verifier that asks "were the night's obligations met" must know which obligations belonged to that night. When the obligation set is written by the run and read by the verifier, and nothing clears it afterwards, the verifier judges a finished night against the previous night's obligations, which are already closed and green. Two wrong verdicts follow from one flaw: a green night with an empty obligation set is recorded as failed, and a night that spent money and recorded nothing passes because the previous night's obligations still satisfy the check. Both were measured on the same gate, on consecutive days. Key the verifier to an occurrence, not a work item; the run ledger, which holds one record per occurrence, is where the obligation set belongs.

## The Autonomy Spectrum

**Level 0 — Manual runs.** A human starts the job and reads the output. Every failure is caught by a person, and every success requires one. Correct for exploration, wrong for anything that must happen nightly.

**Level 1 — Scheduled runs with no gates.** The scheduler fires; the agent does whatever it can. No cap, no done criterion, no liveness check. This is where the published incidents live: an agent that answered every error by provisioning duplicate infrastructure produced a $6,531.30 cloud bill before anyone looked ([Lan Tian's account of the DN42 incident](https://lantian.pub/en/article/fun/ai-agent-bankrupted-their-operator-scan-dn42lantian.lantian); [InfoQ's analysis](https://www.infoq.com/news/2026/07/ai-agents-billing-guardrails)).

**Level 2 — Scheduled runs with health checks.** Each job reports liveness to something that outlives it: a heartbeat on success, an alert on absence, a probe comparing intended against effective configuration. Intent must live in one file: a probe reading a single registry of guarded repositories can assert intended-versus-effective enforcement for all of them, and a status file that is empty when healthy, read by its modification time, catches a probe that has itself stopped ticking.

**Level 3 — Gated fleets with caps and receipts.** A pre-run gate decides affordability and prints the approved work list; the run cannot terminate while its done criteria are unmet; the runner maps every outcome to a distinct exit code; receipts record the evidence that the check passed on the shared main branch. The interesting number here is the failure of self-report: an orchestrator reported "succeeded" while the work item was left open, because nothing mechanically evaluated the done criteria and the agent's own summary was the only thing between a half-finished run and a green result.

**Level 4 — Self-healing fleets.** The job that dies is restarted from its ledger; the lease left by a crashed worker is reclaimed by the next run; the duplicate writer is refused before it starts rather than merged afterwards; a repeated refusal stops the job instead of being retried. Here the fleet's health is a first-class object, checked by a probe whose output a second, independent check reads. No estate in this survey — including the one whose findings fill this document — runs its whole fleet at this level. The honest state of the art is a gated fleet at level 3 with level-4 mechanisms on the jobs that matter most.

## Design Principles

**1. One actor class, one credential set.** Mechanical jobs get no model credentials. Reasoning agents get credentials scoped to the task, set before the session starts and outside the session's own influence. A capability never granted cannot be bent by content the agent reads. The test: if you can name the agent's worst single action and that number is bounded by a mechanism rather than by the model's judgment, the grant is scoped.

**2. The ledger is the run's memory; the driver is code, not a session.** The coordinator should be a deterministic script: it computes the takeable set, writes one record per occurrence, and wakes a reasoning agent only when the set is non-empty. Every fact a successor needs is written before the fact, not after.

```python
import json, os, time

LEDGER = "/var/lib/agent-runs/runs.jsonl"

def append_run_record(record: dict) -> None:
    """Append-only. Written and flushed BEFORE the step it describes."""
    line = json.dumps({"ts": time.time(), **record}, sort_keys=True) + "\n"
    fd = os.open(LEDGER, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, line.encode())
        os.fsync(fd)          # a record that is only in a page cache is not durable
    finally:
        os.close(fd)

def completed_steps(run_id: str) -> set[str]:
    """Resume replays the ledger; no memory of a previous process is required."""
    done = set()
    with open(LEDGER) as fh:
        for line in fh:
            rec = json.loads(line)
            if rec.get("run_id") == run_id and rec.get("outcome") == "step_ok":
                done.add(rec["step"])
    return done
```

**3. Admit the cap before the run; brake in-run on a quantity that only moves one way.** Admission is arithmetic done once: `allowance = budget - reserve`; if the allowance is smaller than what the run needs, the run does not start. That decision cannot stop an overspend after it fires, so the in-run brake is a second, independent control reading the quantity that falls. Assert monotonicity on the first read, and treat a failed read as a stop, not a retry.

```python
class SpendBrake:
    """Brake on remaining credit — a quantity that only falls within a period."""

    def __init__(self, read_remaining, allowance_usd: float):
        self._read = read_remaining
        self.allowance = allowance_usd
        self.start = self._read()

    def spent(self) -> float:
        now = self._read()
        delta = self.start - now
        if delta < 0:                     # the counter moved backwards: the brake
            raise RuntimeError(           # is not measuring spend. Stop the run.
                f"brake read a non-monotonic quantity: {self.start} -> {now}"
            )
        return delta

    def exhausted(self) -> bool:
        return self.spent() >= self.allowance
```

**4. Every outcome gets an exit code, and exactly one of them is success.** A runner that spawns an agent should classify the outcome itself rather than trust the agent's summary. Distinct codes let a scheduler, a watchdog, or a shell `&&` act on them without parsing prose:

| Exit | Meaning | What the record says |
|---|---|---|
| `0` | the run finished and its post-conditions passed | done |
| `2` | refused before any model call (pre-flight failed, or the working copy was already locked) | blocked, nothing spent |
| `3` | the process ran but did not reach its post-conditions — including death by call cap | blocked, never a summary |
| `5` | the same gate refusal repeated and the run was killed | blocked, refusal loop |
| `4` | the runner itself was misused or broken | operator error |

The load-bearing row is the third: **budget exhaustion is a blocked outcome, never a finished one.** Never let a resource limit report as success. If the harness that owns the limit cannot express that, wrap it: a runner that inspects the transcript for a cap marker and writes its own status file stands between a half-finished run and a green dashboard.

**5. Prove liveness from outside the job.** Every scheduled job needs a check that runs somewhere the job does not: a heartbeat on success, and an alert on absence after the expected interval plus a grace buffer (25 hours for a daily job, 169 for a weekly one). The heartbeat carries the run identifier, status, duration, and something about the work done, so the absence check distinguishes "did not run" from "ran and did nothing". Pair it with a configuration probe that asserts intended against effective state and writes an empty status file when healthy; that file's modification time is a liveness signal for the probe itself, so a probe that stops ticking becomes detectable. The gap that cannot be closed from inside the fleet — a scheduler that stopped firing the probe at all — needs a reader on another host.

```python
import os, time

def heartbeat(path: str, run_id: str, status: str, duration_s: float, work_done: int) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w") as fh:
        fh.write(f"{run_id} {status} {duration_s} {work_done}\n")
    os.replace(tmp, path)          # atomic; a reader never sees a partial record

def stale(path: str, expected_interval_s: float, buffer_s: float = 3600) -> bool:
    """The dead-man's switch: alert on the ABSENCE of a success."""
    try:
        return (time.time() - os.path.getmtime(path)) > (expected_interval_s + buffer_s)
    except FileNotFoundError:
        return True                # never fired once counts as stale
```

**6. Resume from the ledger; identify orphans by an owned lease.** Recovery means re-reading the durable record and skipping the steps already marked complete, not remembering what happened. Each step must therefore be idempotent under replay, keyed by run identifier and step name, so a second execution writes the same record rather than a second effect. The harder question is the worker still alive after a restart. The answer is a lease: a record naming the owning process and the time it last spoke. Three cases, and only one is safe to touch.

- The lease's owner is gone and the lease is older than the step's expected duration: the worker is dead, and the lease is reclaimable.
- The lease's owner is gone but the lease is fresh: the worker may be alive behind a lost status update — wait one lease period before reclaiming.
- The lease's owner is alive: the worker is a live orphan doing work. Adopt its output; do not start a second copy.

Skipping the third case is the same defect as the second writer: two processes doing one job, with the loss landing on uncommitted work.

**7. One working copy, one writer, one atomic lock.** The lock is per working copy, not per repository, so two agent worktrees never block each other while a worktree and its main checkout cannot be written at once. It must be atomic to take (`mkdir` is; "check then create" is not), name its owner, be reclaimable when the owner is gone, and refuse a second writer with a distinct exit code rather than silently queueing it.

```python
import os, errno

def take_lock(lockdir: str, owner_pid: int) -> bool:
    try:
        os.mkdir(lockdir)                    # atomic on every local filesystem
    except OSError as exc:
        if exc.errno != errno.EEXIST:
            raise
        return _reclaim_if_stale(lockdir, owner_pid)
    with open(os.path.join(lockdir, "owner"), "w") as fh:
        fh.write(str(owner_pid))
    return True

def _reclaim_if_stale(lockdir: str, owner_pid: int) -> bool:
    owner_file = os.path.join(lockdir, "owner")
    try:
        holder = int(open(owner_file).read().strip())
    except (FileNotFoundError, ValueError):
        return False                         # owner not yet written: treat as live
    try:
        os.kill(holder, 0)                   # signal 0 tests existence only
    except ProcessLookupError:
        os.remove(owner_file)                # the owner is gone: reclaim
        os.rmdir(lockdir)
        return take_lock(lockdir, owner_pid)
    return False                             # a live writer holds it: refuse
```

The lock does not cover the landing. A landing is a fast-forward push, and the version-control layer already refuses a non-fast-forward push, so the lock's job is the write and the remote's job is the landing.

**8. Wait on events, not clocks.** When a run must wait for something slow, end the turn and let the completion notification start it again. Durable timers, callbacks, and completion notifications exist in every serious workflow engine, precisely because a process that waits by polling pays for every interval it waits ([Cloudflare's long-running agent patterns](https://developers.cloudflare.com/agents/concepts/agentic-patterns/long-running-agents); [Temporal on durable execution](https://temporal.io/blog/what-is-durable-execution)). Apply the same rule one level up: a frequent scheduled job needs a cheap pre-run gate that decides whether to wake the model at all, emitting an explicit skip signal so the scheduler records a silent tick rather than a paid one.

```python
import json, os, subprocess

def pre_run_gate(state_path: str) -> None:
    """A model call that discovers 'nothing changed' is pure cost."""
    head = subprocess.run(["git", "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
    previous = open(state_path).read().strip() if os.path.exists(state_path) else ""
    if head == previous:
        print(json.dumps({"wakeAgent": False}))       # skip: zero tokens
        return
    with open(state_path, "w") as fh:
        fh.write(head)
    print(json.dumps({"wakeAgent": True, "context": {"commit": head}}))
```

**9. Repetition is information: the same refusal twice means stop.** A gate that refuses cannot be argued with, and a retry does not change the state the gate read. When the same refusal signature repeats, kill the job rather than retrying it: each retry converts a blocked job into a spender. Implement it as a signature count over the transcript tail, with a threshold of two or three and a distinct exit code, so the fleet report separates a refusal loop from a plain failure.

```python
import hashlib, collections

def refusal_loop(transcript: list[str], threshold: int = 3) -> str | None:
    """A refusal is read in full and answered; it is not a retry token."""
    sig = [hashlib.sha1(t.strip().encode()).hexdigest()
           for t in transcript if t.startswith("REFUSED:")]
    if not sig:
        return None
    most_common, count = collections.Counter(sig).most_common(1)[0]
    return most_common if count >= threshold else None
```

## Field Notes from an Operating Estate

Observations from a practitioner operating a fleet of scheduled and delegated agent jobs, abstracted; the mechanisms are unchanged.

**September 2026 — the brake that could not fire.** The nightly spending brake had been installed for weeks and had never stopped a run. Reading the provider's key-status payload twice inside one run showed why: month-to-date usage read `222.378901663` when the run started and `72.487145487` thirty minutes later, so the subtraction returned `-149.89` and its comparison against an allowance of `3.06` was false on every evaluation. The remaining-credit field on the same response showed that `0.109` had actually been spent. The brake had been reading a windowed counter that can roll, and nothing had ever asserted the quantity was monotonic. Two rules came out of it: brake on remaining credit, which only falls; and raise an error rather than a stop when a brake's quantity moves backwards, so a broken brake is loud on its first run.

**August 2026 — two sessions, one working copy.** Two live sessions wrote the same working copy and branch for three minutes. The reflog showed six rewrites, one session's commit landing between another session's amend and its next commit. Nothing refused the second writer, and a reset by either could have discarded the other's uncommitted work, which existed nowhere else. The fix was structural: an atomic lock taken per working copy, naming the owning process, refusing the second writer with its own exit code, and reclaiming itself when the owner is gone. The loss would have landed on the working tree, which is not recoverable, rather than on committed or pushed work.

**August 2026 — seven workers died at the same wall.** A parent session dispatched sixteen workers. Seven ended at exactly the same call cap without landing their work, and the parent re-dispatched the same items with no prior context — one item six times. Roughly 1,750 calls were consumed at the cap plus a full re-derivation on each continuation, and the only record of which children had landed existed inside the parent's context, which ended when the parent did. This is the observation behind the ledger rule: the coordinator should have been a script writing one record per dispatch and reading the ledger to decide what to do next.

## Evaluation: Real-World Systems

| System | Where durable state lives | What a crash does | Spending brake | Liveness signal |
|---|---|---|---|---|
| [Temporal](https://temporal.io/blog/what-is-durable-execution) | Event history in the service; workflow code replays against it | A worker dies and another replays the history; nondeterministic work is pushed into activities | None built in | Task-queue and workflow-visibility metrics |
| [DBOS](https://www.dbos.dev/blog/durable-execution-coding-comparison) | Workflow and step state in the application's own database | Steps resume from the database record; no external orchestrator to keep alive | None built in | Database rows and its operations console |
| [Cloudflare Workflows](https://developers.cloudflare.com/workflows/) | Managed step state with explicit waits, retries, and replay | Steps replay from the last checkpoint; the agent hibernates and is woken by a callback | Account-level limits; no per-run cap | Workflow instance status |
| [Kubernetes CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) | Job and pod objects only; the container owns its own state | The pod is gone; nothing resumes it unless the container is idempotent | Resource quotas, not money | `lastScheduleTime`/`lastSuccessfulTime`, plus an external dead-man's switch: the controller stops after 100 missed start times |
| [Apache Airflow](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/tasks.html) | Metadata database records task state and retries | The scheduler re-runs the task from its recorded state | None built in | Scheduler heartbeat and DAG-run state |
| [systemd timers](https://man7.org/linux/man-pages/man5/systemd.timer.5.html) | Nothing; the unit owns no ledger | The unit is restarted per policy; resumption is the unit's problem | cgroup resource limits, not money | `systemctl list-timers` and last-trigger timestamps |
| [Anthropic Routines in Claude Code](https://tessl.io/blog/anthropic-adds-routines-to-claude-code-for-scheduled-agent-tasks) | Managed cloud execution with schedule, API, and repository-event triggers | Execution is managed; long-running work continues in the background | Plan-level daily limits | Provider-side run history |
| [Hermes Agent cron](https://hermes-agent.nousresearch.com/docs/user-guide/features/cron) | Per-job execution ledger and durable failure incidents | Runs are isolated sessions; a pre-run script decides whether the model is invoked | Provider-key usage plus a pre-run money gate; a misconfigured job makes no call | `hermes cron doctor` exits non-zero on any actionable issue, including a next-run time parked in the past |

Durable state and crash recovery are solved problems with off-the-shelf answers. Money brakes are not: on the evidence of the documentation cited above, no system in this table ships a per-run spending cap that a reasoning agent cannot talk its way past. Liveness is half-solved: every system here can tell you a job failed, and only those with an external check can tell you a job stopped.

## Recommendations

1. **Separate the actor classes before you schedule anything.** A script-only job gets no model credentials. A reasoning job gets a key whose spend is scoped to that job and whose write reach ends at its working copy.
2. **Write the ledger before you write the scheduler, and make the coordinator a script.** One append-only record per occurrence, flushed to disk, carrying the run identifier, the work item, the start and end, the exit code, and the spend delta; a deterministic driver computes what is takeable from it and dispatches. A session holding that state in its context is a single point of failure for the whole night.
3. **Admit the cap pre-run and brake in-run on remaining credit.** Assert monotonicity on the first read, and make a backwards move an error and a stop.
4. **Give every outcome an exit code, and make cap death a failure.** A resource limit that reports success is a defect; fix the runner, not the dashboard.
5. **Add a heartbeat with a grace buffer to every scheduled job, and a configuration probe to the fleet.** Empty status file when healthy; its modification time is the probe's own liveness signal.
6. **Take a per-working-copy lock and refuse the second writer with its own exit code.** Test the reclaim path by killing the owner, not by waiting for it to happen.
7. **Replace the poll with a completion notification, and gate every frequent job behind a cheap pre-run check.** A model turn that discovers nothing changed is the most expensive way to learn nothing.
8. **Kill on the third identical refusal,** and report it as its own status so a fleet digest can separate a lock from a failure.

## The Hard Truth

These mechanisms are cheap, and teams still do not build them, for one reason: each is invisible until the day it saves you. A cap that never fires, a lock that refuses a second writer, a heartbeat nobody reads — none produce a feature, a demo, or a metric that looks good on a dashboard. The day the fleet runs twenty nights without an incident is the day someone asks whether the pre-run gate can be simplified away.

The evidence is asymmetric. A working brake produces no observation at all, while a dead brake produces one very late and very expensive observation: `-149.89` on a counter that was never monotonic, a reflog with six rewrites in three minutes, a $6,531.30 cloud bill discovered when the card was charged. The feedback loop is therefore inverted: the absence of incidents is read as evidence that the controls are unnecessary, rather than as evidence that they work. Test them deliberately — kill the owner of a lock and watch the reclaim; feed a brake a counter that moves backwards and watch it raise; suspend a job and watch the absence check fire. A fleet whose controls have never been exercised is a fleet whose controls are unproven, and the first exercise will be the real one.

## Summary Checklist

| Question | Good answer | Bad answer |
|---|---|---|
| Do mechanical jobs and reasoning agents hold separate credentials? | Yes — separate keys and scopes; script actors hold no model key | No — one key shared because it was convenient |
| Does anything outlive the process that coordinates the work? | Yes — an append-only ledger, flushed, one record per occurrence | No — the coordinator's context is the only record |
| Is the in-run spending brake built on a monotonic quantity? | Yes — remaining credit, monotonicity asserted on first read | No — a windowed usage field that can roll backwards |
| Is budget exhaustion a failure? | Yes — a distinct blocked exit code, never a summary | No — the capped run reports success |
| Can you detect a job that stopped firing? | Yes — heartbeat on success, alert on absence, grace buffer | No — we would notice when the reports stop |
| Is a crashed worker distinguishable from a live one? | Yes — an owned lease with a last-heard timestamp | No — we restart the step and hope |
| Can two processes write one working copy? | No — an atomic per-working-copy lock refuses the second | No — nothing refuses the second writer |
| Has any of these controls been exercised on purpose? | Yes — induced failures on a schedule | No — we will find out when it matters |

## References

### Durable execution and crash recovery
- [The definitive guide to Durable Execution](https://temporal.io/blog/what-is-durable-execution) — deterministic replay after a crash
- [Durable Execution for AI Agent Runtimes](https://zylos.ai/research/2026-04-24-durable-execution-agent-runtimes) — Temporal, Restate, Inngest, and DBOS compared, April 2026
- [DBOS: durable execution with less code](https://www.dbos.dev/blog/durable-execution-coding-comparison)
- [Cloudflare Agents: long-running agents](https://developers.cloudflare.com/agents/concepts/agentic-patterns/long-running-agents) — hibernate, then wake on a callback
- [Cloudflare Workflows](https://developers.cloudflare.com/workflows/)

### Money brakes and runaway cost
- [OpenAI API budget limits, per user and per run](https://runcycles.io/blog/openai-api-budget-limits-per-user-per-run-per-tenant) — provider control behaviour rechecked July 2026
- [Adding budget limits to OpenAI API calls](https://satgate.io/blog/how-to-add-budget-limits-to-openai-api-calls) — request-path enforcement, not dashboards
- [OpenAI SDK rate limits and cost caps](https://zuplo.com/learning-center/openai-sdk-rate-limits-cost-caps) — fail-open versus fail-closed thresholds, August 2026
- [AI agent budget guards](https://www.nexgismo.com/blog/ai-agent-budget-guards-stop-runaway-api-costs) — the $6,531.30 incident and the loop behind it
- [The agent that spent $47K on itself](https://dev.to/gabrielanhaia/the-agent-that-spent-47k-on-itself-an-autonomous-loop-postmortem-3313) — a self-published postmortem

### Incidents and postmortems
- [An AI agent bankrupted its operator while scanning DN42](https://lantian.pub/en/article/fun/ai-agent-bankrupted-their-operator-scan-dn42lantian.lantian) — the primary account, with community logs
- [AI agents with cloud credentials are outrunning billing guardrails](https://www.infoq.com/news/2026/07/ai-agents-billing-guardrails) — July 2026
- [Cursor-Opus agent destroys a startup's production database](https://www.theregister.com/software/2026/04/27/cursor-opus-agent-snuffs-out-startups-production-database/5224442) — nine seconds, one call, backups included
- [AI agent deleted production data and its backups](https://www.eon.io/blog/ai-agent-data-loss) — why the recovery layer is the last defence
- [State of AI agent incidents 2026](https://runcycles.io/blog/state-of-ai-agent-incidents-2026) — cost, action, and security classes

### Liveness, locks, and identity
- [Kubernetes CronJobs silently fail more than you think](https://dev.to/krissv/kubernetes-cronjobs-silently-fail-more-than-you-think-2nb9) — the 100-missed-schedules limit
- [Cron dead-man switch monitoring](https://web-alert.io/blog/cron-dead-man-switch-monitoring-missed-scheduled-tasks) — heartbeats, grace periods, silent failure shapes
- [Kubernetes: pod failure reasons](https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/) — naming the limit that killed the process
- [OOMKilled and exit code 137](https://spacelift.io/blog/oomkilled-exit-code-137) — 128 plus the signal number
- [AI agent idempotency keys in production](https://cordum.io/blog/ai-agent-idempotency-keys) — run-level versus step-level keys
- [CoSAI: Agentic Identity and Access Management](https://www.coalitionforsecureai.org/wp-content/uploads/2026/04/agentic-identity-and-access-control.pdf) — agents as first-class identities, March 2026
- [Identity is the agentic AI problem nobody has solved](https://www.resilientcyber.io/p/identity-is-the-agentic-ai-problem)

### Harness practice
- [Anthropic: effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — progress files plus version-control history
- [Anthropic: long-running Claude for scientific computing](https://www.anthropic.com/research/long-running-Claude) — a progress file and a test oracle per context
- [Anthropic Routines: scheduled agent tasks in Claude Code](https://tessl.io/blog/anthropic-adds-routines-to-claude-code-for-scheduled-agent-tasks)
- [Hermes Agent: scheduled tasks](https://hermes-agent.nousresearch.com/docs/user-guide/features/cron) — script-only jobs with no model call, pre-run gates that skip a tick at zero cost, a fleet health check that exits non-zero on actionable findings, and separate statuses for execution failure, delivery failure, and a missed fire

### Related Documents in This Series
- [Cost Engineering for LLM Systems](cost-engineering-for-llm-systems.md) — the spending model the brake protects
- [Quality Gates in Agentic Systems](quality-gates-in-agentic-systems.md) — refusal design, fail-open versus fail-closed
- [Reliability Engineering for LLM Applications](reliability-engineering-for-llm-applications.md) — retries, circuit breakers, bounded runs
- [Human-in-the-Loop Patterns](human-in-the-loop-patterns.md) — escalation when nobody is watching
- [Multi-Agent Coordination](multi-agent-coordination.md) — dispatch, re-dispatch, lost coordination state
- [Observability and Monitoring](observability-and-monitoring.md) — detecting failure before a user does

---

*Last reviewed: September 2026. Changed in this revision: new document for the September 2026 refresh, covering actor-class permissions, durable run ledgers, monotonic spending brakes, blocked-versus-finished terminal states, fleet liveness checks, lease-based crash recovery, the single-writer rule, event-driven waiting, and refusal-loop kill signals.*