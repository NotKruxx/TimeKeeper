# Informativa sulla Privacy di TimeKeeper

*Ultimo aggiornamento: 24 Novembre 2025*

## 1. Introduzione
La presente applicazione, **TimeKeeper**, è sviluppata come strumento di utilità per la gestione personale degli orari di lavoro. La privacy dell'utente è il pilastro fondamentale di questo progetto: l'applicazione è progettata per funzionare completamente offline.

## 2. Archiviazione dei Dati (Esclusivamente Locale)
Vogliamo essere estremamente chiari su questo punto:

- **Nessun Server:** TimeKeeper non possiede, non utilizza e non si connette ad alcun server esterno o cloud proprietario.
- **Solo sul Dispositivo:** Tutti i dati inseriti (orari di ingresso/uscita, anagrafica aziende, note e impostazioni) vengono salvati **esclusivamente all'interno del database locale** (SQLite) presente sul tuo dispositivo.
- **Controllo Totale:** Lo sviluppatore non ha alcun modo di accedere, vedere o recuperare i tuoi dati. Se disinstalli l'applicazione senza aver fatto un backup, i dati verranno cancellati definitivamente dal telefono.

## 3. Permessi e Utilizzo delle Funzionalità
L'applicazione richiede l'accesso ad alcune funzionalità del dispositivo solo per scopi specifici e funzionali:

- **Fotocamera:** L'accesso alla fotocamera è richiesto **solo ed esclusivamente** per la scansione dei codici QR necessari per la funzione di timbratura rapida. L'app non scatta foto, non registra video e non invia le immagini scansionate a nessuno. L'elaborazione del codice avviene in tempo reale sul dispositivo.
- **Archiviazione e File:** L'accesso ai file è richiesto solo quando l'utente decide volontariamente di **esportare** (Backup) o **importare** (Ripristino) il database. L'utente sceglie dove salvare il file e l'app non accede ad altre cartelle non autorizzate.

## 4. Condivisione dei Dati
Poiché l'app non si connette a internet per sincronizzare i dati, nessuna informazione lascia mai il tuo dispositivo. L'unica condivisione possibile è quella avviata manualmente da te (ad esempio, se decidi di inviare il file di backup generato via email o WhatsApp).