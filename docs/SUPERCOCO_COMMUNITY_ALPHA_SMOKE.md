# SuperCoCo Community Alpha Consolidated Smoke Gate V1

## Purpose

This is the headless Venus acceptance gate for the Community Alpha core.

It does not replace the focused subsystem witnesses. It orchestrates them and
adds current-source application workloads so a single command proves that the
accepted architecture, NitrOS-9 integration, and representative accelerated
applications still operate together.

## Required floor

- NitrOS-9 must descend from
  `6dee8c3133d8e22c84c04f1faa68d5e874117dc5`.
- XRoar must descend from
  `d9661764ae4ecaeb54bf55fb404843efae74c1fa`.

Later accepted descendants remain eligible.

## Coverage

The gate proves:

- full NitrOS-9 boot to Shell+ on `/DD`;
- ARCH0-R1J native 640x480 INDEX4 video;
- Community Alpha full-speed five-CPU native-video gate;
- ARCH0-R1K MEDIA graphics services;
- ARCH0-R1L audio services;
- current-source `scgfxanim`;
- current-source `scavdemo`;
- retained S1 service/IRQ/network closure;
- published S2B6 style-9 masked alpha, buffered row strips, dirty rectangles,
  and close/reopen lifetime closure;
- dirty-mirror work bounds of 16 rows for a normal one-row write and 32 rows
  for the wrapped two-row case.

Venus is headless. Human visual and audible quality acceptance remains a
separate WSL/graphical-host release gate.

## Run

```sh
scripts/test-supercoco-community-alpha-smoke.sh
```

Successful completion ends with:

```text
RESULT: PASS
COMMUNITY_ALPHA_CORE=READY
```

After this gate is accepted, Community Alpha core changes should retain this
entire gate as a regression boundary.
