# "Re-check now" does not say what it checks

## The problem

The menu carries a button labelled **Re-check now**. It calls `AgentModel.refresh()`,
which runs `proctor_doctor` and the activity poll immediately: it re-reads whether
the agent is answering and whether the permission grants are in place, instead of
waiting for the next automatic poll.

The label names the verb and omits the object, so it reads as a command with no
subject. A person who has not read the source cannot tell what is being re-checked
or why they would want to.

## Is it worth keeping at all

The honest case against: the model already polls, so the state converges without
anybody pressing anything, and a button that only makes something happen sooner is
usually clutter.

The honest case for: it has exactly one real moment. Permissions are granted in
System Settings, in another application, and macOS does not reliably tell an app
that a grant it was denied has just been given. That is precisely when somebody
comes back to the menu and wants to say "look again now". Proctor's whole onboarding
is two permission grants, so the moment is not rare.

So the decision is between:

1. **Relabel** to name the object — permissions and whether the agent is answering —
   in the app's own register. Sentence case, no title case, matching the other items.
2. **Remove**, and rely on the poll, if the poll interval is short enough that the
   window between granting and noticing is not worth a control.

Either is defensible. What is not defensible is leaving a control whose label
describes nothing.

## Worth knowing

- The same refresh already runs on a timer; check the interval before deciding, since
  it is the whole argument for removal.
- Granting Screen Recording already kickstarts the agent so its cached
  `SCShareableContent` probe re-runs, with an "Applying…" transient. Whatever is
  decided here should not contradict that path.
- The menu's other items are "Proctor Status…", "Run Setup Again…", "Show Run Panel",
  "Pause Run" / "Stop Run" and "Quit Proctor". Match their register.
