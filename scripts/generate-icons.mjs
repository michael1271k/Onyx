/**
 * Render every icon Onyx ships from one source image.
 *
 *   npm run icons                 # uses resources/icon.png
 *   node scripts/generate-icons.mjs path/to/other.png
 *
 * WHY THIS REPLACED WHAT WAS HERE
 * The previous version took no input at all: it inlined a ~75-line SVG template
 * and rasterised that. So "changing the app icon" meant editing gradient stops
 * in a shell script, and the icon it drew was still on the neon palette
 * (#16F5C3 / #5BFF9D) the app abandoned. Dropping a new artwork into
 * resources/ did nothing, and running the script would quietly overwrite it.
 */
import sharp from 'sharp'
import { mkdirSync, existsSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

const SOURCE = resolve(process.argv[2] ?? 'resources/icon.png')

/**
 * The flat behind the artwork.
 *
 * Apple REJECTS an app icon with an alpha channel, so transparency has to be
 * composited away rather than carried. Sampled from the source corners.
 */
const MATTE = '#000309'

const TARGETS = [
  // The app and watch appiconsets each declare exactly one universal 1024
  // entry with this filename, so their Contents.json needs no edit — only the
  // bytes change.
  { file: 'native/Onyx/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png', size: 1024 },
  { file: 'native/OnyxWatch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png', size: 1024 },
]

/**
 * NO ROUNDED CORNERS, and no circular mask for the watch.
 *
 * iOS and watchOS apply their own superellipse / circle. Baking a radius in
 * (the old SVG had rx="112") shows as a double corner once the OS mask lands on
 * top. And the watch's inscribed circle is ±317px wide where the ribbon spans
 * ±150, so nothing needs insetting to survive the crop.
 */
async function render({ file, size, crop, sharpen, greyscale }) {
  const out = resolve(file)
  mkdirSync(dirname(out), { recursive: true })

  let img = sharp(SOURCE)
  if (crop) {
    const { width } = await img.metadata()
    const side = Math.round(width / crop)
    const off = Math.round((width - side) / 2)
    img = img.extract({ left: off, top: off, width: side, height: side })
  }
  img = img
    .resize(size, size, { fit: 'cover', kernel: 'lanczos3' })
    .flatten({ background: MATTE })
    .removeAlpha()
  if (greyscale) img = img.greyscale()
  if (sharpen) img = img.sharpen({ sigma: sharpen })

  await img.png({ compressionLevel: 9, palette: false }).toFile(out)
  return out
}

async function main() {
  if (!existsSync(SOURCE)) {
    console.error(`✗ no source image at ${SOURCE}`)
    console.error('  Put a square PNG of at least 1024×1024 at resources/icon.png,')
    console.error('  or pass one: node scripts/generate-icons.mjs path/to/icon.png')
    process.exit(1)
  }

  const { width, height, format } = await sharp(SOURCE).metadata()
  if (width !== height) {
    console.error(`✗ ${SOURCE} is ${width}×${height}. An app icon must be square.`)
    process.exit(1)
  }
  if (width < 1024) {
    console.error(`✗ ${SOURCE} is ${width}×${width}. iOS needs 1024×1024; upscaling would soften it.`)
    process.exit(1)
  }
  if (format !== 'png') {
    // Not fatal — sharp reads it fine — but a lossy source bakes its artefacts
    // into all six outputs, and around a specular highlight that shows.
    console.warn(`⚠ ${SOURCE} is ${format}, not png. Re-save it losslessly when you can.`)
  }

  for (const t of TARGETS) {
    const out = await render(t)
    const tag = t.greyscale ? ' (greyscale — iOS applies the tint)' : ''
    console.log(`  ${String(t.size).padStart(4)}px  ${out.replace(`${process.cwd()}/`, '')}${tag}`)
  }

  console.log('\n✓ icons written. Now run: npx cap sync ios')
}

main().catch((err) => {
  console.error('✗ icon generation failed:', err.message)
  process.exit(1)
})
