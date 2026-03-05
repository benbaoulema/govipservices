# Intermediate Stops (Travel)

This Flutter module mirrors the web logic used for route stop suggestions.

## Source of truth

The CI hubs catalog is synced from the web project sources:

- `components/voyage/services/ciRouteHubs.generated.ts`
- `components/voyage/services/routeHubsCatalog.ts`

## Flutter files

- `lib/features/travel/data/ci_route_hubs.dart`
- `lib/features/travel/data/route_stop_suggestion_service.dart`

## Current behavior

1. Merge generated hubs with strategic transport hubs (strategic entries take precedence by `id`).
2. Build a candidate area between departure and arrival (expanded bounds).
3. Keep hubs close to the route corridor and not too close to start/end.
4. Score by proximity + priority + hub kind (`city` preferred).
5. De-duplicate nearby ETA candidates.
6. Distribute final stops along trip progression.
7. Compute suggested intermediate price from departure with ratio and currency rounding.

## Notes

- Price rounding:
  - `XOF`: floor by 500
  - other currencies: rounded integer
- Suggested price uses an `0.8` factor vs direct route ratio, same as web approach.
