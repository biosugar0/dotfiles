# draw.io 図作成ガイド

## 核心ルール

### 1. フォント設定
- `mxGraphModel` に `defaultFontFamily` を設定しても不十分
- **各mxCellのstyleに `fontFamily=Noto Sans JP;` を明示する**

```xml
<!-- 悪い例 -->
<mxCell style="text;html=1;fontSize=18;" />

<!-- 良い例 -->
<mxCell style="text;html=1;fontSize=18;fontFamily=Noto Sans JP;" />
```

### 2. 矢印配置
- XML記述順 = 描画順（先に書いたものが背面）
- **矢印は最初に記述して最背面に配置**

```xml
<root>
  <mxCell id="0"/>
  <mxCell id="1" parent="0"/>
  <!-- 矢印を先に（最背面） -->
  <mxCell id="arrow" style="edgeStyle=..." edge="1" parent="1">...</mxCell>
  <!-- 図形を後に（前面） -->
  <mxCell id="box" style="rounded=1;..." vertex="1" parent="1">...</mxCell>
</root>
```

### 3. ラベル配置
- **矢印とラベルは最低20px離す**
- テキスト要素への矢印接続は `exitY/entryY` が効かないことがある
- 明示的に座標を指定する

```xml
<!-- 良い例: 明示的座標指定 -->
<mxCell id="arrow" edge="1" parent="1">
  <mxGeometry relative="1" as="geometry">
    <mxPoint x="190" y="300" as="sourcePoint"/>
    <mxPoint x="490" y="300" as="targetPoint"/>
  </mxGeometry>
</mxCell>
```

### 4. テキストサイズ
- **フォントサイズは標準の1.5倍（18px推奨）**
- **日本語テキストは幅を1文字あたり30-40px確保**

```xml
<!-- 悪い例: 幅不足で改行される -->
<mxGeometry x="240" y="60" width="200" height="40" />

<!-- 良い例: 十分な幅 -->
<mxGeometry x="140" y="60" width="400" height="40" />
```

### 5. 背景設定
- `page="0"` で透明背景

## XML基本構造

```xml
<mxfile host="Electron">
  <diagram name="Page-1" id="unique-id">
    <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1"
                  tooltips="1" connect="1" arrows="1" fold="1" page="0"
                  pageScale="1" pageWidth="827" pageHeight="1169"
                  defaultFontFamily="Noto Sans JP">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <!-- ここに要素を追加 -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

## PNG変換コマンド

```bash
drawio -x -f png -s 2 -t -o output.png input.drawio
```

| オプション | 説明 |
|-----------|------|
| `-x` | エクスポートモード |
| `-f png` | PNG形式 |
| `-s 2` | 2倍スケール（高解像度） |
| `-t` | 透明背景 |
| `-o` | 出力ファイル |

## チェックリスト

作成後に確認:
- [ ] 全テキスト要素に `fontFamily` が設定されているか
- [ ] フォントサイズは18px以上か
- [ ] 矢印が最背面（XML先頭）に配置されているか
- [ ] 矢印とラベルが被っていないか（20px以上離れているか）
- [ ] 日本語テキストが意図しない改行をしていないか
- [ ] PNGで視覚確認したか

## AWS構成図

AWSアーキテクチャ図を作成する場合は `references/aws-icons.md` を参照。
