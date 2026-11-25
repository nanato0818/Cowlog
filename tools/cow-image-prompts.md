# 牛の画像生成プロンプト（2026-11-14）

組み込み image_gen を使用。生成時は常に `transparent_background: true`。元画像は生成ツールの保存先に保持し、採用画像を1024×1024のRGBA PNGへ整えて配置する。GLBと旧生成スクリプトは保持するが、表示画像の再生成には使わない。

## 1. 全身の初回生成（毛並みが細かいため不採用）

Use case: stylized-concept. Create one 1024x1024 transparent PNG app asset: a normal adult Holstein dairy cow, anatomically realistic proportions, smooth high-quality 3D CGI product visualization, subtle surface detail, NOT photograph, NOT cartoon, NOT toy or figurine, normal small eyes and neutral natural bovine face. Full body standing, viewed from front-right about 30 degrees with head on LEFT of image, all four legs individually visible. Entire animal including ears tail and hooves within frame, occupies 85% of canvas width, centered with generous top and bottom margin. Large irregular black patches, white blaze on face, white belly and lower legs, pink-gray muzzle. Thin dark charcoal collar following neck, small tracking device under throat, one yellow ear tag, no horns. Soft overhead studio lighting and weak ambient fill, no ground shadow, no floor. Background truly transparent alpha, no white halo, no checkerboard drawn, no lettering.

## 2. 採用する滑らかな全身への編集

Use case: precise-object-edit. Edit target is the referenced cow. Preserve exact anatomy, four legs, pose, camera, collar tracking device and yellow ear tag, black and white pattern. Change surface rendering only: remove detailed hair/fur strands and skin wrinkles; create smooth softly shaded high quality realistic 3D CGI cow with matte surfaces, not a photo, not a toy, not cartoon. Natural cow face, small eyes. Make edges clean without white fringe or stray pixels. 1024x1024 true transparent background, no ground or shadow. Fit full animal centered at 85% of canvas width with equal left/right margins and generous vertical margins.

## 3. 茶色への編集（2の採用画像を参照）

Use case: precise-object-edit. Input image is edit target. Recolor ONLY this cow's coat to a uniform light warm Jersey dairy-cow brown, with slightly paler muzzle surround. Remove all black-white coat patches. Preserve EXACT silhouette, anatomy, pose, four legs, face, camera angle, size, placement, smooth realistic 3D CGI rendering, soft overhead lighting, dark gray thin collar and small throat tracking device, yellow ear tag, eyes and hooves. No fur detailing, no toy, no cartoon. Genuine transparent background, no shadow, no ground, clean edges. Square canvas.

## 4. 胸像（2の採用画像を参照）

Use case: stylized-concept. Input image is reference for cow identity, proportions, face, coat pattern and rendering style. Create a 1024x1024 transparent app portrait asset of this Holstein: head through base of neck ONLY, camera near frontal turned about 20 degrees, normal realistic adult cow anatomy, small natural eyes, neutral face, smooth high-quality realistic 3D CGI with soft overhead light, no detailed fur, not cartoon or toy. White blaze on face, irregular black patches, pink-gray nose, thin charcoal collar and small tracking device under throat, one yellow ear tag, no horns. Center HEAD at canvas center. Both ears including tips entirely inside an imaginary circle centered (512,512) radius 465; ears span about 75% canvas width, leave generous top margin. Neck base ends near bottom of circle, no torso or legs. Transparent alpha, no disk or background, no white fringe or shadow, no text.

## 5. 茶色の胸像（4の画像を編集）

Use case: precise-object-edit. Edit target is referenced Holstein head-and-neck portrait. Change ONLY coat color to uniform light warm Jersey brown, paler muzzle surround, remove all black-white patches. Preserve exact head and neck silhouette, ear positions, eye size, nose, anatomy, near-frontal 20-degree camera, image composition and placement, thin charcoal collar and small throat tracking device, one yellow ear tag. Smooth matte realistic high quality 3D CGI, no detailed fur, not cartoon, not toy, no smile. True transparent alpha background and clean edges without fringes. Do not add torso or legs. Square image.

## 採用元と後処理

- `holstein`: `/Users/murakami/.codex/generated_images/01a1d90d-50c7-7b72-8cb3-73c4d347b14c/exec-55718cfc-83ef-4fde-beee-66f1f1386c72.png`
- `brown`: `/Users/murakami/.codex/generated_images/01a1d90d-50c7-7b72-8cb3-73c4d347b14c/exec-012bfe1f-3b06-46ea-880c-08eaba03c97c.png`
- `holstein_avatar`: `/Users/murakami/.codex/generated_images/01a1d90d-50c7-7b72-8cb3-73c4d347b14c/exec-d390adb9-8cdc-42ee-b0ca-38c3813762b3.png`
- `brown_avatar`: `/Users/murakami/.codex/generated_images/01a1d90d-50c7-7b72-8cb3-73c4d347b14c/exec-97c685de-0c1c-4230-92b5-80f13fccda89.png`

再生成には上記プロンプトを順に image_gen に渡す。生成モデルには非決定性があるため、完全に同じ絵になる保証はない。

後処理は `python3 tools/prepare_cow_images.py FULL_HOLSTEIN FULL_BROWN AVATAR_HOLSTEIN AVATAR_BROWN`。依存は Pillow と numpy。生成された1254px画像を透過のまま1024pxキャンバスへ配置し、全身の幅を870px（約85%）に、胸像を最大800×850pxに揃える。低アルファの不可視な残片だけを除去。未設定は茶色を輝度変換して淡いグレー（#C8D1CC付近）へ明るくし、黄色い耳標と暗い目・鼻・首輪・端末を保持する。茶色と未設定はアルファと構図が完全一致。

検証：全6枚が1024×1024 RGBA、外周アルファ0。胸像の実体（アルファ>32）は中心から493px以内で、半径512pxの円内。明るいアプリ背景と暗い背景、54px・32pxの円形縮小を目視確認。採用元は参照編集により構図を維持しているが、毛並み等の微細な描画は完全なピクセル一致ではない。


