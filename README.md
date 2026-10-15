# helix-p4d 2026.1 (sourcegraph layout)

Official Perforce Helix Core **2026.1** in the same filesystem layout as
[sourcegraph/helix-docker](https://github.com/sourcegraph/helix-docker)
2023.2 / 2024.1:

| Path | Role |
| --- | --- |
| `/p4` | volume (`P4HOME`) |
| `/p4/root` | `configure-helix-p4d.sh -r` argument |
| `/p4/root/root` | live `P4ROOT` (`db.*`, `server.id`) |
| `/p4/root/journals` | `P4JOURNAL=../journals/journal` |
| `/p4/root/logs` | `P4LOG=../logs/log` |
| `/p4/root/archives` | `server.depot.root=../archives` |
| `/p4/root/etc` | persisted `/etc/perforce` (p4dctl) |

## Build

```sh
cd helix-p4d
./build.sh helix-p4d:2026.1
```

Ubuntu 24.04 (Noble) + `helix-p4d=2026.1-3089746~noble` (pulls `p4-server`).
Focal is out of standard support; the P4 root layout is unchanged.

`init.sh` remaps the image `perforce` user to the UID that owns
`/p4/root/root`, so a Focal-era volume does not need a recursive `chown`
of the archives. If the tree is owned by root, only the metadata dirs
(`root`, `journals`, `logs`) are given to `perforce`.

## Upgrade an existing 2023.2 volume

1. Checkpoint and snapshot the **whole** `/p4` bind (not only `root/root`).
2. Stop the old container. Do not `down -v`.
3. Point compose at the image you just built. Keep the same `/p4` mount and
   the same `NAME` / `P4NAME` / `P4USER` / `P4PASSWD` / `P4CASE` / `P4CHARSET`.
4. Start it. `init.sh` sees `/p4/root/root/db.counters`, runs `p4d -xu`,
   and starts p4dctl. It does **not** run `setup.sh`.

```sh
docker compose stop
# edit image: helix-p4d:2026.1
docker compose up -d
docker compose logs -f
p4 info          # 2026.1, Server root /p4/root/root, serverid genx-p4
p4 configure show
p4 triggers -o
```

2026.1 forces **security=4** even if you had 3. Rotate the super-user
password on 2023.2 first so it meets level 4.

Rollback is the `/p4` snapshot plus the old sourcegraph image. After `-xu`,
2023.2 cannot read the tables.

## Fresh server

Same env as sourcegraph. First start runs `configure-helix-p4d.sh -r /p4/root`
and gets `/p4/root/root`.
