# Label Conventions

## Status labels

- `status/planned`
- `status/in-progress`
- `status/done`

## Type labels

- `type/feature`
- `type/bug`
- `type/docs`
- `type/chore`

## Area labels

- `area/ui`
- `area/providers`
- `area/history`
- `area/stats`
- `area/docs`
- `area/release`

## Priority labels

- `priority/high`
- `priority/medium`
- `priority/low`

## Suggested setup command

```bash
gh label create status/planned --color 0E8A16 --repo streichsbaer/OpenScribe || true
gh label create status/in-progress --color FBCA04 --repo streichsbaer/OpenScribe || true
gh label create status/done --color 1D76DB --repo streichsbaer/OpenScribe || true

gh label create type/feature --color 5319E7 --repo streichsbaer/OpenScribe || true
gh label create type/bug --color D73A4A --repo streichsbaer/OpenScribe || true
gh label create type/docs --color 0075CA --repo streichsbaer/OpenScribe || true
gh label create type/chore --color C2E0C6 --repo streichsbaer/OpenScribe || true

gh label create area/ui --color BFD4F2 --repo streichsbaer/OpenScribe || true
gh label create area/providers --color C5DEF5 --repo streichsbaer/OpenScribe || true
gh label create area/history --color FEF2C0 --repo streichsbaer/OpenScribe || true
gh label create area/stats --color F9D0C4 --repo streichsbaer/OpenScribe || true
gh label create area/docs --color D4C5F9 --repo streichsbaer/OpenScribe || true
gh label create area/release --color FEF2C0 --repo streichsbaer/OpenScribe || true

gh label create priority/high --color B60205 --repo streichsbaer/OpenScribe || true
gh label create priority/medium --color FBCA04 --repo streichsbaer/OpenScribe || true
gh label create priority/low --color 0E8A16 --repo streichsbaer/OpenScribe || true
```

## Rule

Keep labels stable so saved issue queries remain useful over time.
