# Test fonts

Used only by `test/screenshots_test.dart`, never shipped: Flutter tests draw every glyph as a box
unless real fonts are loaded, and a screenshot of boxes proves nothing about Arabic shaping or a
mixed-direction line.

| Family              | Stands in for                                      |
| ------------------- | -------------------------------------------------- |
| Noto Sans           | the device's system font, in the default theme     |
| Noto Sans Arabic    | the device's Arabic fallback, in the default theme |
| Noto Serif          | the custom theme's own font                        |
| Noto Naskh Arabic   | the custom theme's Arabic font                     |

All four are the Noto Project's, under the SIL Open Font License 1.1 (`OFL.txt`), which names no
Reserved Font Name. They are subset to Latin, general punctuation and Arabic to keep the repository
small; nothing else is changed.
