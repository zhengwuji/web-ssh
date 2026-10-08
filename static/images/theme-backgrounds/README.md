# 主题背景资源

PNG 原图存放在服务目录之外：`assets/theme-backgrounds/`；被服务的目录只保留更小的
WebP 派生文件，分辨率同为 1672 x 941。请保留原图以便日后重新生成。

使用 Pillow 编码，参数为 `format='WEBP', quality=90, method=6`
（`arctic-frost.png` 使用 quality 89，以保持在每张图 150,000 字节的预算之内）。
Pillow 仅是制作工具，应用本身不需要额外依赖。

重新生成后，请用该 WebP 文件 SHA-256 摘要的前 16 个十六进制字符，
更新 `static/css/style.css` 中对应的 URL。随后运行静态资源引用测试与浏览器主题测试，
以验证内容版本、体积预算、外观与已保存主题的行为。
