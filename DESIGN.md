# Design

## Brand Idea

Blinlin is a focused communication system. The visual metaphor is a signal grid: people, groups, calls, and moments are connected through clean channels, not decorative surfaces. The mark and product UI should feel precise, current, and trustworthy.

## Color

- Primary: `#6366F1` for selected navigation, primary actions, focus rings, and active communication states.
- Ink: `#1E293B` for primary text.
- Body: `#64748B` for secondary text.
- Muted: `#94A3B8` for metadata and disabled text.
- Page: `#F8FAFC` for the base background.
- Surface: `#FFFFFF` for sheets, lists, and panels.
- Line: `#E2E8F0` for subtle separators.
- Success: `#10B981`.
- Warning: `#F59E0B`.
- Danger: `#EF4444`.

Use color semantically. Primary is rare and purposeful. Do not use gradient text, decorative gradient backgrounds, side-stripe borders, or colored accents without state meaning.

## Typography

Use the platform sans stack through Flutter's default Material typography. Product UI uses a fixed scale:

- Page title: 22sp / 700
- Section title: 17sp / 700
- Row title: 16sp / 600
- Body: 14sp / 400
- Metadata: 12sp / 500

Letter spacing stays at 0. Do not use display-style oversized type inside dense product screens.

## Layout

Mobile is bottom-navigation first. Wider screens use a side rail with the same information architecture. Page structure is:

1. Context header
2. Primary task surface
3. Secondary actions through inline rows, bottom sheets, or overflow menus

Use a 4dp spacing scale: 4, 8, 12, 16, 20, 24, 32, 40. Lists should use separators and grouped sections rather than card grids. Cards are reserved for repeated rich content such as moments, media previews, and account modules.

## Components

- App shell: adaptive navigation, clear unread badges, no decorative header copy.
- Lists: avatar -> title -> subtitle -> metadata, with pinned/muted/unread status visible.
- Chat: stable header, message timeline, consistent bubbles, compact composer, media/tool actions in a bottom sheet or horizontal tray.
- Contacts: top task rows for new friends, groups, QR scan, and search; friend list stays scannable.
- Moments: composer is a deliberate publishing surface; feed cards use image grids and visible privacy state.
- Mine: account summary, wallet, QR, settings, logs, and feature center grouped by task.

## Motion

Use short state transitions, 150-220ms. Motion should indicate navigation, selection, message arrival, composer expansion, and sheet opening only. No page-load choreography.

## Platform

Android/iOS/Web/desktop should keep the same information architecture. Desktop can show rail navigation and wider content, but must not expose a different feature model.
