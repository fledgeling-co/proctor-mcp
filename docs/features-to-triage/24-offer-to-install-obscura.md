# Offer to install Obscura when it is missing

## The problem

PRO-0020 taught Proctor to recognise a browser target and hand the page to
Obscura. It does that whether or not Obscura is on the machine. A person who
follows the advice and finds no such command has been sent somewhere that does not
exist, which is worse than not being advised at all: the handoff reads as an
instruction from a tool that knows what it is talking about.

`proctor_doctor` reports what Proctor itself needs. It says nothing about the tool
Proctor tells other people to use.

## What it should do

Notice that `obscura` is absent, say so where the recommendation is made, and offer
to install it rather than leaving somebody to work out how.

Three surfaces, and they want different things:

- **The handoff object.** When Obscura is missing, the recommendation should say so
  in the same breath rather than printing a command that will fail. The model
  reading it can then tell the person, instead of pasting a command and reporting a
  confusing error.
- **`proctor_doctor`.** A tool Proctor routes work to is part of whether Proctor is
  ready to do its job, so its presence belongs in the health report alongside the
  grants and the shortcuts CLI, which is already reported.
- **The app.** This is where "offer to install" actually means something: the
  status window already walks a person through two permission grants, and a missing
  helper tool is the same shape of problem with a much easier fix.

## The part that needs deciding rather than defaulting

**What "offer to install" is allowed to do.** Downloading and running an installer
on somebody's machine, from a background agent that already holds Accessibility and
Screen Recording, is a much bigger thing than reporting a missing grant. The
conservative reading is that Proctor never installs anything: it detects, explains,
shows the exact command, and lets a person run it. The convenient reading is a
button. This is a decision about what an agent with these permissions may do
unattended, and it should be made deliberately, in the spec, with the answer
written down.

Whatever is chosen, an install must never happen as a side effect of a tool call. A
model driving Proctor asked to click a button in an app; it did not ask to change
what is installed on the machine.

## Worth knowing

- Detection is `obscura --version` or a PATH lookup, and it should be cached rather
  than shelled out on every handoff. It can also change under a long-lived agent,
  so a cache needs an expiry or an invalidation.
- A PATH lookup from a launchd agent does not see a login shell's PATH. Proctor's
  agent runs from launchd, so the usual Homebrew locations have to be checked
  explicitly rather than assumed to be on the path it inherited.
- The repo already reports `shortcutsCLIAvailable` in `proctor_doctor`; match that
  shape rather than inventing a second one.
