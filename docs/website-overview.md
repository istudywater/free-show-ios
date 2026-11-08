---
title: FreeShow Controller
description: A native iPad companion for browsing and controlling FreeShow presentations over your local network.
updated: 2026-11-07
status: Development preview
---

# FreeShow Controller

## Website introduction

### Your presentation controls, wherever you need them.

FreeShow Controller turns your iPad into a portable operator console for FreeShow. Browse your service, choose slides, move through a presentation, and search the desktop Bible library while your computer handles the screens and media.

Designed for churches, volunteers, and presentation operators, the app brings the controls you use during a service into a native, touch-friendly iPad interface.

**Short description:** A native iPad companion for controlling FreeShow presentations, navigating service items, and preparing scripture over your local network.

**Suggested development-stage call to action:** Follow development.

## What you can do

### Browse the service

View FreeShow projects and their ordered service items. Open a native presentation to browse its slide grid, with text previews and rendered thumbnails when the desktop can provide them. Follow the desktop project or browse another project locally before explicitly selecting it on the desktop.

### Control slides your way

Previous and Next stay within reach at the bottom right. The Tap to live toggle lets you choose how slide selections work:

- **Off:** Tap to preview; hold for half a second to send that slide live.
- **On:** A single tap sends the slide directly to live output.

Tap to live starts off. Slides are checked against fresh desktop content before presentation, and disabled slides cannot be activated.

### Clear output and go live

The bottom-left Clear output / Go live button clears active outputs, including audio, backgrounds, overlays, and timers. Once the slide layer is clear, Go live presents the selected slide. If no slide is selected, it requests restoration of the desktop's cached output. Supported selected media starts after confirmation. Desktop output locks and available cached state still apply.

### Keep preview and live state distinct

Live indicators distinguish the slide on output from the slide selected for preview. Current and next slide text help operators prepare the next cue. Monitoring follows the first active desktop output; some controls affect multiple active outputs.

### Find and present scripture

Choose an individual translation from the desktop Bible library. Search a reference, preview a passage, or find text matches, then explicitly present the prepared passage. Same-chapter verse ranges and lists are supported, with available translation attribution displayed.

Scripture shares the operator's authenticated connection. Available content depends on the Bibles and any provider access configured in FreeShow Desktop. Bible collections and cross-chapter selections are not currently supported.

### Start supported media

Start existing image, video, PDF, audio, overlay, and player items when they have a unique explicit name in the active desktop project. FreeShow renders the media, and Previous / Next can navigate PDF pages. Ambiguous, unnamed, or unsupported items remain desktop-operated; the app is not a media editor.

### Connect locally

Find nearby FreeShow computers or enter an address manually. Use the desktop RemoteShow password when configured. Remember the last successful computer and optionally save its password in the device Keychain.

Automatic reconnection refreshes desktop state. Presentation commands are not replayed after interruption. When a command's result is uncertain, the app asks the operator to check actual output before continuing.

### Rehearse without a computer

An offline demo supplies a sample service, slide controls, media state, and demonstration scripture text. Demo mode does not connect to or control a real presentation computer.

## A layout built for iPad

Wider layouts place the service list, slide grid, and live/preview information side by side. Portrait and smaller windows use selectable panes. The control dock stays available while browsing, with touch targets, accessibility labels, and a VoiceOver Go live action on slides.

## What you need

- An iPad running iPadOS 17 or later.
- A computer running FreeShow Desktop with RemoteShow enabled, normally on port 5510.
- Both devices on a local network that allows them to communicate.
- Local-network permission for the iPad app and any required desktop firewall access.

FreeShow Desktop handles presentation rendering and physical display outputs. FreeShow Controller is a companion control app, not a standalone presentation renderer or a replacement for the desktop application.

## Visual identity and artwork

The identity follows the Smixx app family: orange, charcoal, near-white, and a restrained cyan accent. Its distinct symbol combines a presentation screen and play triangle. The startup screen uses dimensional geometric panels, with the logo and FreeShow Controller wordmark centered in the charcoal panel.

![FreeShow Controller icon](../Design/Brand/freeshow-controller-logo-v1.png)

![FreeShow Controller startup screen](../Design/Brand/freeshow-controller-start-v2.png)

## Publication notes — for the website builder

The sections above are draft product copy grounded in the implemented app. Keep the following release qualifications visible where appropriate, and remove these editorial notes from the public page once resolved:

- **Availability:** Development preview installed through Xcode. No App Store listing, download link, release date, or pricing has been supplied. Do not show a working download or purchase button yet.
- **Evidence:** The user has confirmed MacBook Air discovery, connection, and live presentation control after updating FreeShow, reportedly to approximately 1.6.7. This is user-reported evidence, not a verified version-support matrix.
- **Preview status:** The user reported missing slide previews. Image retries, automatic live-show loading, compatibility handling, and diagnostic messages have been improved; the rebuilt app still needs device retesting to confirm the original issue is resolved.
- **Validation:** 182 automated checks and simulator builds pass. Full scripture, media, multiple-output, accessibility, network-interruption, and extended-service acceptance remain pending.
- **Scope:** Presentation editing, uploads, media-library management, cloud sync, and internet-based remote control are not implemented product features.
- **Relationship and licensing:** Describe this as a companion for FreeShow. Official endorsement, App Store distribution, pricing, and the repository's own open-source license have not been established; do not claim them.
- **Artwork:** Use the supplied icon and revision-2 startup artwork. The generated assets and exact prompts are recorded in `Design/Brand/Branding.md`. Avoid using screenshots containing private network addresses, connection passwords, or unapproved presentation content.

## Suggested page structure

1. Hero: app name, short description, icon, and Follow development call to action.
2. Operator workflow: browse, preview, then go live.
3. Feature sections: slide navigation, output control, scripture, media, and local connection.
4. iPad screenshots once the latest device build is reviewed.
5. Requirements and development availability.
6. Clear companion-app relationship to FreeShow.
