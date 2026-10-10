# Microsoft Azure - Uppgift 3

**Student:** Kardo Jabari

**Kurs:** Microsoft Azure

**Vecka:** 36 - Nätverk och säkerhet

Lösningen bygger vidare på Novatrix webbserver och identitetsmodell. Webben ligger i ett eget subnät. Ett separat privat subnät förbereds för senare backend och lagring.

**Status:** Genomförd och verifierad den 10 oktober 2026, inklusive VG-delen. Webbservern är frigjord efter testerna.

## Lösningens delar

- `v36/network/network.json` - nätverket som ARM-kod för VG.
- `v36/scripts/apply-network.sh` - kontrollerar befintlig miljö, visar ändringar och tillämpar mallen.
- `v36/scripts/verify-network.sh` - visar subnät, NSG-kopplingar och regler.
- `v36/scripts/verify-traffic.sh` - startar VM:n kort, kontrollerar trafik och HTTP, och frigör den efteråt.
- `v36/config.example.sh` - exempel för lokal konfiguration.

## Nätverksdesign

| Del | Adressrymd | Funktion |
| --- | --- | --- |
| vnet-novatrix | 10.10.0.0/16 | Befintligt virtuellt nätverk |
| snet-novatrix-web | 10.10.1.0/24 | Befintlig webbserver med publik IP |
| snet-novatrix-private | 10.10.2.0/24 | Privat subnät för senare backend |

HTTP och HTTPS tillåts till webbsubnätet. Övrig inkommande trafik nekas, även SSH. Administration sker via Azure med behörigheterna från uppgift 2. HTTPS-regeln gör att port 443 tillåts i nätverket; ett fungerande HTTPS-anrop kräver dessutom TLS-konfiguration i webbservern.

Det privata subnätet tillåter endast förberedd trafik på port 443 från webbsubnätet och saknar standardåtkomst ut till internet. En backend eller ett lagringskonto skapas inte i detta moment. Ett Azure Storage-konto hamnar inte automatiskt i subnätet; privat åtkomst till lagringen måste konfigureras i lagringsmomentet.

Webbsubnätet tillåter utgående TCP på port 443 till internet och till det privata subnätet. Porten är avsedd för TLS/HTTPS, men en NSG kontrollerar inte att trafiken verkligen är krypterad. Azures inbyggda DNS och nödvändiga plattformstrafik hanteras separat av Azure och blockeras inte av en vanlig NSG-regel. Övrig utgående trafik nekas. Det innebär bland annat att paketkällor som bara använder HTTP inte kan användas utan en avsiktlig regeländring.

## Förberedelse

Kör i Azure Cloud Shell med Bash och administratörens konto:

Koden utgår från att miljön från uppgift 1 redan finns: resursgruppen, VNet, webbsubnätet, VM:n, nätverkskortet och den publika IP-adressen. Den skapar nätverksreglerna och det privata subnätet; den skapar inte en ny webbserver.

```bash
cp v36/config.example.sh v36/config.local.sh
# Fyll i rätt prenumeration och tenant i config.local.sh.
bash v36/scripts/apply-network.sh
```

Skriptet visar först vad mallen skulle ändra. Det befintliga nätverket och webbsubnätets adressrymd kontrolleras före driftsättningen. Den gamla NSG:n tas inte bort; webbservern kopplas till den nya regeluppsättningen. Webbserverns IP-adress och identitetsroller ändras inte av skriptet.

## Verifierade resultat

- ARM-driftsättningen `novatrix-v36-network` slutfördes med status `Succeeded`.
- Båda subnäten finns och har varsin NSG. Webbserverns nätverkskort ligger i webbsubnätet och använder den nya webb-NSG:n.
- Network Watcher IP flow verify gav följande resultat medan VM:n kördes:

| Riktning | TCP-port | Resultat | Regel |
| --- | --- | --- | --- |
| Inkommande | 80 och 443 | Allow | Allow-Web |
| Inkommande | 22 och 8080 | Deny | Deny-Other-Inbound |
| Utgående till internet | 443 | Allow | Allow-Internet-TLS |
| Utgående till internet | 80 | Deny | Deny-Other-Outbound |

- Ett riktigt HTTP-anrop till den publika IP-adressen lyckades och svaret innehöll Novatrix-sidan.
- VM:n frigjordes efter testerna. Slutstatus är `VM deallocated`.

IP flow verify visar hur nätverksreglerna bedömer trafik; det är inte ett verkligt anslutningsförsök. HTTP verifierades även med ett riktigt anrop. HTTPS-webbtjänsten och trafik till en privat backend har inte verifierats. Det privata subnätet är förberett och innehåller ännu ingen backend.

Kör verifieringen igen vid behov:

```bash
bash v36/scripts/verify-network.sh
bash v36/scripts/verify-traffic.sh
```

Trafikskriptet startar VM:n och frigör den vid normal avslutning eller ett skriptfel. Om processen tvångsstängs måste frigöringen kontrolleras manuellt.

## VG och skydd i flera lager

Separata subnät begränsar trafik mellan webben och den framtida backenddelen. NSG-regler begränsar både inkommande och utgående trafik. Öppen SSH tas bort från den aktiva regeluppsättningen. Azure-administration skyddas av konto, MFA och de avgränsade rollerna från uppgift 2.

Designen minskar exponeringen för SSH-försök och obehörig trafik mellan olika delar av miljön. Den ersätter inte applikationsskydd, TLS-certifikat eller framtida lagringsbehörigheter.

## Kostnad och fortsatt arbete

Ingen Bastion, NAT Gateway eller Azure Firewall har skapats. VM:n behöver bara köras vid testning. Disk och publik IP kan fortfarande kosta när VM:n är frigjord, beroende på fria kvoter. Azure-budgetar varnar men utgör inget hårt kostnadstak.

När fler subnät eller andra nätverksinställningar tillkommer behöver ARM-mallen granskas och utökas innan den körs igen. Skriptet stoppar om det hittar andra subnät eller oväntade adressrymder.

PDF med enkel förklaring, diagram och bildbevis lämnas separat. Privat konfiguration och råa bevisfiler ingår inte i repot.
