#!/bin/bash
#
# Собирает Mishi Glance и упаковывает в DMG-установщик в стиле coderok.ru.
#
#   ./scripts/make-dmg.sh                  собрать тем, что есть в связке ключей
#   ./scripts/make-dmg.sh --create-cert    разрешить Xcode создать Developer ID
#   ./scripts/make-dmg.sh --notarize       собрать, отправить в Apple, прикрепить штамп
#
# Учётные данные для нотаризации — один раз, в связку ключей (пароль никуда
# не попадает, кроме Keychain):
#
#   xcrun notarytool store-credentials mishi-notary \
#       --apple-id ВАШ@APPLE.ID --team-id FKD7Y4FR88 --password APP-SPECIFIC-PASSWORD
#
# Запасной вариант — переменные окружения AC_APPLE_ID / AC_PASSWORD / AC_TEAM_ID.
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/Mishi Glance.app"
DMG="$BUILD/Mishi Glance.dmg"
ARCHIVE="$BUILD/Mishi Glance.xcarchive"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
VOLUME="Mishi Glance"

NOTARIZE=0
ALLOW_UPDATES=""
for arg in "$@"; do
    case "$arg" in
        --notarize)    NOTARIZE=1 ;;
        --create-cert) ALLOW_UPDATES="-allowProvisioningUpdates" ;;
        *) echo "Неизвестный аргумент: $arg"; exit 2 ;;
    esac
done

# --- окружение для сборки образа -------------------------------------------
PY="${MG_PYTHON:-$ROOT/scripts/.venv/bin/python}"
if [[ ! -x "$PY" ]]; then
    echo "==> Создаю окружение для сборки DMG"
    python3 -m venv "$ROOT/scripts/.venv"
    "$ROOT/scripts/.venv/bin/pip" install --quiet --upgrade pip
    "$ROOT/scripts/.venv/bin/pip" install --quiet dmgbuild pillow fonttools
    PY="$ROOT/scripts/.venv/bin/python"
fi
DMGBUILD="$(dirname "$PY")/dmgbuild"

# Xcode 26 может подписывать облачным сертификатом, ключ которого не виден
# из CLI. Поэтому наличие Developer ID определяем двумя способами: по связке
# ключей (тогда им можно подписать и образ) и по факту успешного экспорта.
devid_in_keychain() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/'
}
DEVID="$(devid_in_keychain)" || true

mkdir -p "$BUILD"
rm -rf "$APP"

# --- 1. Сборка -------------------------------------------------------------
if [[ -n "${DEVID:-}" || -n "$ALLOW_UPDATES" ]]; then
    # Дистрибутивный путь: archive + exportArchive. Только он снимает
    # com.apple.security.get-task-allow — с этим entitlement Apple отклоняет
    # нотаризацию, а обычная сборка Release его оставляет.
    echo "==> Архивирую для распространения"
    rm -rf "$ARCHIVE"
    xcodebuild archive \
        -project "Mishi Glance.xcodeproj" -scheme "Mishi Glance" \
        -configuration Release -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE" -derivedDataPath "$WORKDIR/dd" $ALLOW_UPDATES \
        | grep -E "error:|BUILD" || true

    echo "==> Экспортирую с Developer ID"
    rm -rf "$WORKDIR/export"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
        -exportPath "$WORKDIR/export" $ALLOW_UPDATES \
        | grep -E "error:|EXPORT" || true

    if [[ ! -d "$WORKDIR/export/Mishi Glance.app" ]]; then
        echo "!! Экспорт не удался. Скорее всего нет сертификата Developer ID Application."
        echo "   Xcode → Signing & Capabilities → Signing Certificate → Developer ID Application,"
        echo "   либо запустите: ./scripts/make-dmg.sh --create-cert"
        exit 1
    fi
    cp -R "$WORKDIR/export/Mishi Glance.app" "$BUILD/"
else
    echo "==> Developer ID не найден — обычная сборка Release"
    echo "   Приложение запустится только на этой машине; Gatekeeper на чужом Mac его отклонит."
    xcodebuild -project "Mishi Glance.xcodeproj" -scheme "Mishi Glance" \
        -configuration Release -destination 'generic/platform=macOS' \
        -derivedDataPath "$WORKDIR/dd" build \
        | grep -E "error:|BUILD" || true
    cp -R "$WORKDIR/dd/Build/Products/Release/Mishi Glance.app" "$BUILD/"
fi

# --- 2. Проверка подписи ---------------------------------------------------
echo "==> Проверяю подпись"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/   /'
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
if grep -q "get-task-allow" <<<"$ENTS"; then
    echo "   ВНИМАНИЕ: в бандле остался com.apple.security.get-task-allow"
    [[ $NOTARIZE -eq 1 ]] && { echo "!! Нотаризация с ним не пройдёт."; exit 1; }
else
    echo "   get-task-allow отсутствует — годится для нотаризации"
fi

# --- 2b. Нотаризация приложения --------------------------------------------
# Штамп на самом бандле, а не только на образе: иначе приложение,
# скопированное из DMG на машину без интернета, нечем проверить —
# а автообновление копирует его именно так.
notary_args() {
    local profile="${AC_KEYCHAIN_PROFILE:-mishi-notary}"
    if xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
        echo "--keychain-profile $profile"
    elif [[ -n "${AC_APPLE_ID:-}" && -n "${AC_PASSWORD:-}" ]]; then
        local team="${AC_TEAM_ID:-$(grep -m1 DEVELOPMENT_TEAM "Mishi Glance.xcodeproj/project.pbxproj" \
            | sed -E 's/.*= *([A-Z0-9]+);.*/\1/')}"
        echo "--apple-id $AC_APPLE_ID --team-id $team --password $AC_PASSWORD"
    fi
}

if [[ $NOTARIZE -eq 1 ]]; then
    NOTARY_ARGS="$(notary_args)"
    if [[ -z "$NOTARY_ARGS" ]]; then
        echo "!! Нет учётных данных для нотаризации. Сохраните их один раз:"
        echo "   xcrun notarytool store-credentials mishi-notary \\"
        echo "       --apple-id ВАШ@APPLE.ID --team-id FKD7Y4FR88 --password APP-SPECIFIC-PASSWORD"
        exit 1
    fi
    echo "==> Заверяю приложение (1/2)"
    APPZIP="$BUILD/app-for-notary.zip"
    rm -f "$APPZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$APPZIP"
    xcrun notarytool submit "$APPZIP" $NOTARY_ARGS --wait
    rm -f "$APPZIP"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
fi

# --- 3. Фон установщика ----------------------------------------------------
echo "==> Рисую фон в фирменных цветах"
"$PY" "$ROOT/scripts/dmg_background.py" "$ROOT/scripts/dmg-background.png" >/dev/null
# Многомасштабный TIFF: Finder возьмёт @2x на Retina и @1x на обычном экране.
tiffutil -cathidpicheck \
    "$ROOT/scripts/dmg-background-1x.png" \
    "$ROOT/scripts/dmg-background.png" \
    -out "$ROOT/scripts/dmg-background.tiff" >/dev/null

# --- 4. Сборка образа ------------------------------------------------------
echo "==> Собираю DMG"
rm -f "$DMG"
"$DMGBUILD" -s "$ROOT/scripts/dmg_settings.py" \
    -D app="$APP" -D background="$ROOT/scripts/dmg-background.tiff" \
    "$VOLUME" "$DMG"

# Идентичность берём из уже подписанного приложения — она достовернее, чем
# догадки по связке ключей.
APP_IDENTITY="$(codesign -dvv "$APP" 2>&1 \
    | grep -m1 "^Authority=Developer ID Application" | sed 's/^Authority=//')" || true

if [[ -n "${APP_IDENTITY:-}" ]] && codesign --force --sign "$APP_IDENTITY" \
        --timestamp "$DMG" 2>/dev/null; then
    echo "==> Образ подписан: $APP_IDENTITY"
elif [[ -n "${APP_IDENTITY:-}" ]]; then
    echo "==> Образ не подписан: ключ от «${APP_IDENTITY}» недоступен из терминала"
    echo "   (Xcode подписал приложение облачным сертификатом.)"
    echo "   Само приложение внутри подписано верно — для нотаризации этого достаточно."
    echo "   Чтобы подписывать и образ, создайте локальный сертификат:"
    echo "   Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
fi

# --- 5. Нотаризация --------------------------------------------------------
if [[ $NOTARIZE -eq 1 ]]; then
    if [[ -z "${APP_IDENTITY:-}" ]]; then
        echo "!! Приложение не подписано Developer ID — нотаризация невозможна."
        exit 1
    fi
    PROFILE="${AC_KEYCHAIN_PROFILE:-mishi-notary}"
    if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
        echo "==> Отправляю в Apple (профиль связки ключей «${PROFILE}»). Обычно 1–5 минут."
        xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    else
        if [[ -z "${AC_APPLE_ID:-}" || -z "${AC_PASSWORD:-}" ]]; then
            echo "!! Нет учётных данных для нотаризации. Сохраните их один раз:"
            echo "   xcrun notarytool store-credentials $PROFILE \\"
            echo "       --apple-id ВАШ@APPLE.ID --team-id FKD7Y4FR88 --password APP-SPECIFIC-PASSWORD"
            exit 1
        fi
        TEAM="${AC_TEAM_ID:-$(grep -m1 DEVELOPMENT_TEAM "Mishi Glance.xcodeproj/project.pbxproj" \
            | sed -E 's/.*= *([A-Z0-9]+);.*/\1/')}"
        echo "==> Отправляю в Apple (команда $TEAM). Обычно 1–5 минут."
        xcrun notarytool submit "$DMG" \
            --apple-id "$AC_APPLE_ID" --team-id "$TEAM" --password "$AC_PASSWORD" --wait
    fi
    echo "==> Прикрепляю штамп"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

# --- 6. Итог ---------------------------------------------------------------
echo
rm -rf "$ARCHIVE"
echo "Готово: $DMG  ($(du -h "$DMG" | cut -f1))"
echo -n "Вердикт Gatekeeper: "
spctl --assess --type execute -v "$APP" 2>&1 | tail -1 | sed "s|^.*: ||"
