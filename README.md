# Owen

Privacy-first mobilny klient czatu z modelami AI (Android/Flutter).
Łączysz się **własnymi kluczami API** do dowolnego endpointu kompatybilnego z
OpenAI — nic nie przechodzi przez żaden serwer pośredniczący.

## Zasady prywatności

- **Brak telemetrii i analityki.** Jedyny ruch sieciowy idzie do endpointów,
  które sam skonfigurujesz.
- **Klucze API** trzymane wyłącznie w keystore systemu (Android Keystore) przez
  `flutter_secure_storage` — nigdy w bazie ani w plikach aplikacji.
- **Historia rozmów** w lokalnej bazie **szyfrowanej SQLCipher**; klucz bazy jest
  losowy (256 bit CSPRNG) i również leży tylko w keystore.
- „Usuń wszystkie dane" czyści dostawców, klucze i całą historię z urządzenia.

## Obsługiwani dostawcy

Jeden uniwersalny adapter na format OpenAI `/chat/completions` (ze streamingiem),
więc działa m.in. z: **DeepSeek**, OpenAI, OpenRouter, Groq, Mistral, Together,
oraz lokalnie **Ollama** i **LM Studio**. Gotowe presety w ekranie dodawania
dostawcy; dowolny inny endpoint dodasz ręcznie (Base URL + klucz + lista modeli).

Przykład DeepSeek:
- Base URL: `https://api.deepseek.com/v1`
- Modele: `deepseek-chat`, `deepseek-reasoner`

## Funkcje (MVP)

- Streaming odpowiedzi (SSE, token po tokenie).
- Lokalna historia wielu rozmów.
- Wybór dostawcy i modelu na rozmowę + własny system prompt.
- Render Markdown, bloków kodu i LaTeX (`gpt_markdown`), kopiowanie odpowiedzi.

## Architektura

```
lib/
  core/theme.dart                  motyw Material 3 (jasny/ciemny)
  data/
    models/                        ProviderProfile, Conversation, ChatMessage
    secure/secret_store.dart       klucze API + klucz bazy → keystore
    db/app_database.dart           SQLCipher (sqflite_sqlcipher)
    llm/openai_client.dart         streaming /chat/completions
  state/                           Riverpod: providery + kontroler czatu
  features/
    conversations/                 lista rozmów
    chat/                          ekran czatu, composer, bąbelki
    settings/                      dostawcy + edycja endpointu/klucza
```

Zarządzanie stanem: **Riverpod 3**. Baza i keystore inicjalizowane w `main()` i
wstrzykiwane przez `ProviderScope.overrides`.

## Uruchomienie

```bash
flutter pub get
flutter run              # na podłączonym urządzeniu / emulatorze Android
flutter analyze
flutter test
```

Wymaga skonfigurowanego Android SDK (cmdline-tools + zaakceptowane licencje:
`flutter doctor --android-licenses`).
