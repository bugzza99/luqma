# Geography, Addressing and Maps

## The problem
Edku's streets are not systematically numbered and Google's map data there is thin.
People navigate by landmarks: "next to Al-Nour pharmacy".

## The solution — zones first, map second
Structured text addressing is the primary mechanism; the map is a supporting layer.
An address is: `zone` (from an admin-defined list) + street + landmark + free note +
building/floor/apartment, with an optional pin.

`zone` earns its place by doing three jobs at once:
1. Resolving delivery fee via `zones.defaultDeliveryFee`.
2. Constraining which merchants may receive the order via `merchants.servedZones`.
3. Giving couriers a coarse destination before they read any detail.

## The branded map
Google Maps SDK renders the map; **displaying a map in the mobile SDK is free** — the billed
Google services are Places, Geocoding and Directions, none of which this design uses.
A custom map style JSON recolours the map into the brand palette so it does not look like
a default Google map.

`landmarks` are Luqma's own Firestore documents drawn as a marker layer on top. The admin
creates them: pharmacies, mosques, tuk-tuk stops, schools. They cost nothing and they are the
actual fix for couriers circling.

Turn-by-turn navigation is delegated to the installed Google Maps app by intent. Building
in-app navigation would cost far more and be less accurate than the app couriers already use.
