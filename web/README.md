# Unplugged — web prototipas

> Pagrindinė programėlė dabar yra natyvi iOS (`../ios`). Šis aplankas — ankstesnis web prototipas, paliktas palyginimui.

Viena bendra elektromobilių įkrovimo platforma: visų operatorių stotelės, realaus laiko užimtumas, kelionių planavimas, atsiskaitymas vienoje vietoje ir atsakingo stotelių naudojimo skatinimas (grace period, progresyvus „idle fee“, taškai, pranešimai apie piktnaudžiavimą).

Vilnius Hack 2026 · iššūkis Nr. 13.

> Tai prototipas. Visi stotelių, kainų ir užimtumo duomenys yra **demonstraciniai** (`src/lib/data`). Operatorių pavadinimai naudojami tik iliustracijai.

## Paleidimas

```bash
npm install
npm run dev      # http://localhost:3000
npm test         # logikos testai (vitest)
npm run build
```

Reikia Node 20+.

## Kas yra

| Ekranas | Kelias | Ką daro |
|---|---|---|
| Žemėlapis | `/` | Visų operatorių stotelės žemėlapyje ir sąraše, filtrai (laisvos, ≥ 50 kW, tinka mano automobiliui, operatorius), „Mano vieta“ |
| Stotelė | `/stations/[id]` | Jungčių būsenos (laisva / kraunasi / baigė, bet stovi / užimta nesikraunant / neveikia), kaina, užimtumas pagal valandas, tikimybė rasti laisvą vietą, geriausias laikas, virtuali eilė, įkrovimo pradžia ir apmokėjimas |
| Įkrovimas | `/session` | Aktyvi sesija: progresas → pranešimas „baigta“ → dinaminis grace period (5–15 min.) → progresyvus mokestis → kvitas ir taškai. Yra laiko pagreitis demonstracijai |
| Kelionė | `/plan` | Automobilis + baterijos lygis + tikslas → kur, kada ir kiek krautis, su kokiu % atvyksite, kaina; vengia užimtų stotelių pagal istorinius duomenis |
| Taškai | `/rewards` | Balansas, lygiai, kaip uždirbti, privalumų keitimas, istorija |
| Pranešti | `/report` | Pranešimas apie užimtą vietą (numeris, nuotrauka) → patikimumas iš nuotraukos, stotelės duomenų ir kitų patvirtinimų → sankcijų laiptai |
| Operatoriams | `/operator` | Vid. „idle“ laikas, piktnaudžiavimo atvejai, paklausa pagal valandas, kiek papildomų vairuotojų galima aptarnauti be naujų stotelių (su reguliuojamu poveikio modeliu) |

## Struktūra

```
src/
  app/                  puslapiai (Next.js App Router)
  components/           UI: AppShell (navigacija, pranešimai), StationMap (Leaflet), ui.tsx (bazinės dalys)
  lib/
    types.ts            domeno tipai
    data/               demonstraciniai duomenys: stotelės, operatoriai, automobiliai, miestai
    logic/              verslo logika be UI — čia keičiamos taisyklės
      idleFee.ts        grace period pagal paklausą, mokesčio pakopos, lubos
      availability.ts   užimtumas, tikimybė rasti laisvą vietą, piko valandos
      charging.ts       įkrovimo kreivė (lėtėja virš 50/80 %), laikas ir kWh
      tripPlanner.ts    kelionės planavimas
      points.ts         taškų taisyklės, privalumai, lygiai
      reports.ts        pranešimų patikimumas ir sankcijos
      analytics.ts      operatorių / miesto analitika
    store.tsx           kliento būsena (išsaugoma localStorage)
```

## Dizainas

Dabartinis vaizdas — neutralus karkasas. Spalvos yra CSS kintamieji `src/app/globals.css` (`--brand`, `--ok`, `--warn`…), o bazinės dalys (`Card`, `Button`, `Badge`…) — `src/components/ui.tsx`, todėl naują dizainą galima pritaikyti daugiausia tose dviejose vietose.

## Kas toliau

- Tikri duomenys: operatorių API (OCPI) arba backend'as su realaus laiko būsenomis
- Tikras maršrutas (OSRM / Google Directions) vietoj tiesios linijos × 1,2
- Mokėjimai (Stripe / Paysera) ir paskyros
- Push pranešimai (PWA) vietoj pranešimų programėlės viduje
