# Unplugged

Viena bendra elektromobilių įkrovimo platforma — natyvi iOS programėlė (Swift, SwiftUI). Visų operatorių stotelės, realaus laiko užimtumas, kelionių planavimas, atsiskaitymas vienoje vietoje ir atsakingo stotelių naudojimo skatinimas: dinaminis „grace period“, progresyvus „idle fee“, taškai ir pranešimai apie piktnaudžiavimą.

Vilnius Hack 2026 · iššūkis Nr. 13.

> Prototipas. Visi stotelių, kainų ir užimtumo duomenys yra **demonstraciniai** (`ios/Unplugged/Models/DemoData.swift`). Operatorių pavadinimai naudojami tik iliustracijai.

## Paleidimas

Reikia **Mac** su **Xcode 16** ar naujesniu (nemokamai App Store).

1. `git clone https://github.com/KristyzZ/Unplugged.git`
2. Atidarykite `ios/Unplugged.xcodeproj`
3. Viršuje pasirinkite simuliatorių (pvz., iPhone 16) ir spauskite ▶ (`⌘R`)

**Savo iPhone:** prijunkite telefoną, Xcode → projektas *Unplugged* → *Signing & Capabilities* → *Team* pasirinkite savo Apple ID. Jei rašo, kad Bundle ID užimtas, pakeiskite `lt.vilniushack.unplugged` į bet ką unikalaus. Telefone: *Nustatymai → Bendrieji → VPN ir įrenginių valdymas* → patvirtinkite kūrėją.

Simuliatoriuje vietą galima nustatyti per *Features → Location → Custom Location* (Vilnius: 54.6872, 25.2797).

## Ekranai

| Skirtukas | Ką daro |
|---|---|
| Žemėlapis | Apple Maps su visų operatorių stotelėmis, filtrai (laisvos, ≥ 50 kW, tinka mano automobiliui, operatorius), sąrašas pagal atstumą. Viršuje dešinėje — analitika operatoriams |
| Stotelė | Jungčių būsenos (laisva / kraunasi / baigė, bet stovi / užimta nesikraunant / neveikia), kaina, užimtumas pagal valandas (Swift Charts), tikimybė rasti laisvą vietą, virtuali eilė, įkrovimo pradžia ir apmokėjimas, maršrutas Apple Maps |
| Įkrovimas | Sesija: progresas → pranešimas „baigta“ (tikras iOS pranešimas) → grace period 5–15 min. → progresyvus mokestis → kvitas ir taškai. Laiko pagreitis 1×–300× demonstracijai |
| Kelionė | Automobilis + baterijos lygis + tikslas → kur, kada ir kiek krautis, su kokiu % atvyksite, kaina, maršrutas žemėlapyje |
| Taškai | Balansas, lygiai, kaip uždirbti, privalumų keitimas, istorija, demo duomenų atstatymas |
| Pranešti | Numeris + nuotrauka → patikimumas iš nuotraukos, stotelės duomenų ir kitų vartotojų patvirtinimų → sankcijų laiptai |

## Struktūra

```
ios/
  Unplugged.xcodeproj
  Unplugged/
    App/          programėlės įėjimas, skirtukai, pranešimų juostos
    Models/       domeno tipai ir demo duomenys
    Logic/        verslo taisyklės be UI — čia keičiama logika
      IdleFee.swift        grace period pagal paklausą, mokesčio pakopos, lubos
      Availability.swift   užimtumas, tikimybė rasti laisvą vietą
      Charging.swift       įkrovimo kreivė, laikas ir kWh
      TripPlanner.swift    kelionės planavimas
      Points.swift         taškai, privalumai, lygiai
      Reports.swift        pranešimų patikimumas, sankcijos
      Analytics.swift      operatorių / miesto analitika
    State/        AppModel (būsena, išsaugoma), pranešimai, vieta
    UI/Theme.swift  spalvos, formatavimas, bazinės dalys — dizainas keičiamas čia
    Features/     ekranai
web/              ankstesnis web prototipas (Next.js)
```

## Kas toliau

- Tikri duomenys: operatorių API (OCPI) arba backend'as
- Tikras maršrutas (MKDirections) vietoj tiesios linijos × 1,2
- Mokėjimai (Apple Pay / Stripe) ir paskyros
- Live Activity įkrovimo progresui užrakinimo ekrane
