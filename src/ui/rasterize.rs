//! Shared SVG-to-Bevy-Image rasterization for embedded icons.

use bevy::asset::RenderAssetUsages;
use bevy::image::ImageSampler;
use bevy::prelude::*;
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};
use resvg::{tiny_skia, usvg};

/// Rasterizes an embedded SVG string into a Bevy [`Image`].
///
/// Returns a 1×1 transparent pixel image if parsing or rasterization fails.
/// Since all SVGs are compiled into the binary via `include_str!`, failure
/// only occurs on build errors or corrupted assets.
pub(crate) fn rasterize_svg(svg: &str) -> Image {
    let options = usvg::Options::default();
    let Ok(tree) = usvg::Tree::from_str(svg, &options) else {
        return fallback_image();
    };
    let size = tree.size().to_int_size();
    let Some(mut pixmap) = tiny_skia::Pixmap::new(size.width(), size.height()) else {
        return fallback_image();
    };

    resvg::render(
        &tree,
        tiny_skia::Transform::identity(),
        &mut pixmap.as_mut(),
    );

    let mut image = Image::new_fill(
        Extent3d {
            width: size.width(),
            height: size.height(),
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        pixmap.data(),
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    );
    image.sampler = ImageSampler::nearest();
    image
}

fn fallback_image() -> Image {
    Image::new_fill(
        Extent3d {
            width: 1,
            height: 1,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &[0, 0, 0, 0],
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    )
}
