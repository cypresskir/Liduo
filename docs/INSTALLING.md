# Установка Liduo

Нужны **macOS 26 или новее** и **MacBook на Apple silicon** с датчиком угла крышки.
Xcode для установки готового приложения не нужен. Версия 0.2.5 доступна в
[GitHub Releases](https://github.com/cypresskir/Liduo/releases/tag/v0.2.5).

Сборка имеет ad-hoc-подпись, но не сертификат Developer ID и не проверена Apple.
Это не ограничение лицензии MIT. Разрешайте запуск, только если доверяете источнику.

## Homebrew

Если Homebrew еще не установлен, откройте «Терминал» и выполните
[команду с официального сайта](https://brew.sh/):

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

После установки выполните команды из раздела **Next steps**, который покажет
установщик, чтобы `brew` стала доступна в терминале. Затем установите Liduo:

```sh
brew tap cypresskir/liduo https://github.com/cypresskir/Liduo
brew install --cask cypresskir/liduo/liduo
```

Используется собственный tap проекта. После установки разрешите запуск
**только Liduo**, если доверяете сборке, и откройте приложение:

```sh
xattr -dr com.apple.quarantine "/Applications/Liduo.app"
open "/Applications/Liduo.app"
```

Команда удаляет у Liduo атрибут карантина. Общая проверка приложений macOS остается
включенной. Если нет прав на `/Applications`, установите в свою папку:

```sh
brew install --cask --appdir="$HOME/Applications" cypresskir/liduo/liduo
xattr -dr com.apple.quarantine "$HOME/Applications/Liduo.app"
open "$HOME/Applications/Liduo.app"
```

## npx

Нужен **Node.js 22 или новее** с npm/npx. Команда получает установщик прямо из
тега GitHub, скачивает готовое приложение и проверяет SHA-256:

```sh
npx --yes --allow-git=all github:cypresskir/Liduo#v0.2.5 --allow-unnotarized
open "/Applications/Liduo.app"
```

Параметр `--allow-git=all` разрешает загрузку из Git только для этой команды npx.
Начиная с npm 12 она запрещена по умолчанию; глобальные настройки npm менять не нужно.
Подробнее: [параметр allow-git](https://docs.npmjs.com/cli/v12/using-npm/config#allow-git).

Флаг `--allow-unnotarized` разрешает снять карантин только с устанавливаемой Liduo.
Без него установщик сохраняет карантин. После первой попытки запуска разрешите
приложение в **Системных настройках → Конфиденциальность и безопасность → Все равно
открыть**. Этот способ описан в [инструкции Apple](https://support.apple.com/en-us/102445).

Для установки без прав администратора:

```sh
npx --yes --allow-git=all github:cypresskir/Liduo#v0.2.5 --allow-unnotarized --app-dir "$HOME/Applications"
open "$HOME/Applications/Liduo.app"
```

Отдельного пакета `liduo` в npm проект не публикует. Используйте полный адрес
`github:cypresskir/Liduo#v0.2.5`, чтобы запускать установщик из этого репозитория.

## Первый запуск

В Liduo нажмите **«Разрешить доступ…»**, разрешите запись экрана в настройках macOS
и перезапустите приложение, если система попросит. Команда `xattr` не выдает доступ
к экрану. Предпросмотр со встроенной картинкой работает без этого разрешения.

Если macOS сообщает об обнаруженном вредоносном ПО или повреждении файла,
не используйте снятие карантина: заново скачайте выпуск и проверьте его.

## Обновление и удаление

Начиная с 0.2.5, выберите **«Проверить обновления…»** в меню Liduo или в общих
настройках. Приложение покажет новую версию, скачает ее и предложит установку
с перезапуском. Настройки эффекта сохранятся. Автоматическая проверка раз в день
включается отдельно; без нее запросы выполняются только по вашей команде.

Этот способ работает после установки и через Homebrew, и через npx. Терминал
для последующих обновлений не нужен. Если предпочитаете обновлять вручную через
менеджер пакетов, сначала закройте Liduo:

```sh
# Homebrew
brew update
brew upgrade --cask --greedy cypresskir/liduo/liduo

# npx: замените v0.2.5 на тег нового выпуска
npx --yes --allow-git=all github:cypresskir/Liduo#v0.2.5 --allow-unnotarized --replace
```

Если использовали `--appdir` или `--app-dir`, повторите ту же папку при обновлении.
npx сохраняет старую копию рядом как `Liduo.previous-<время>.app` и выводит ее путь.
После проверки новой версии старую копию можно переместить в Корзину.
Homebrew может снова установить карантин после обновления; при необходимости
повторите команду `xattr` для Liduo.

У ad-hoc-сборок подпись меняется между выпусками: macOS может попросить заново
разрешить запись экрана. Установщик не меняет и не сбрасывает системные разрешения.

Лента обновлений и архив подписаны ключом Liduo. При ошибке проверки подписи
установка отменяется. Подробнее о подготовке обновлений: [UPDATES.md](UPDATES.md).

Для удаления через Homebrew: `brew uninstall --cask cypresskir/liduo/liduo`.
После установки через npx закройте Liduo и перенесите ее из папки установки в Корзину.

Подготовка выпуска: [RELEASING.md](RELEASING.md). Официальная документация:
[Homebrew taps](https://docs.brew.sh/Taps), [Homebrew Cask](https://docs.brew.sh/Cask-Cookbook),
[npx](https://docs.npmjs.com/cli/v11/commands/npx/).
