# Proxmox branding implementation

## Purpose

New containers receive an independent information panel in the Proxmox Summary
view. The panel distinguishes the official application from the ImmacularIT
native-LXC adaptation and does not reuse Community Scripts promotional content.

## Panel contents

The host launcher applies the panel only after the generic builder completion
hook has run. It contains:

- the official Nginx Proxy Manager name and artwork;
- a link to the official upstream repository;
- a statement that upstream is officially Docker-based;
- a statement that this project is an unofficial native Proxmox LXC adaptation;
- the approved ImmacularIT logo;
- links to the ImmacularIT profile, adaptation repository, and issue tracker;
- useful text and links even if external images fail to load.

It contains no Community Scripts donation, discussion, script catalogue, or
promotional links.

## Image sources

The development branch references:

- `https://nginxproxymanager.com/github.png`
- `https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/15c268e6fd0e6f9b441aa9f785c278c3f580171b/assets/immacularit-logo.png`

The ImmacularIT asset URL is pinned to an exact commit. CI downloads each image
and verifies the PNG signature and a minimum file size.

A real browser test in Proxmox is still required. The test must confirm image
rendering, aspect ratio, alternative text, all links, attribution, and readable
fallback content.

## Tags

The launcher preserves valid user-supplied tags, removes only the automatic
`community-script` tag, de-duplicates values, and ensures these project tags:

- `nginx-proxy-manager`
- `reverse-proxy`
- `immacularit`
- `webserver`

## Maintenance

When changing an asset:

1. verify that its license and branding use permit the intended display;
2. pin project-owned or approved artwork to an immutable revision;
3. update the URL in the launcher, assets notes, CI, and this document;
4. run repository validation;
5. verify the result in a real Proxmox browser before recording it as passed.
