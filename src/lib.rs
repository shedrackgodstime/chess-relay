//! Application entry crate for Chess Relay.

mod app;
mod chess;
mod screens;
mod theme;
mod ui;

use anyhow::Result;
use bevy::prelude::*;

/// Builds and runs the Chess Relay application.
pub fn run() -> Result<()> {
    App::new()
        .add_plugins(app::AppPlugin)
        .add_plugins(theme::ThemePlugin)
        .add_plugins(screens::ScreenPlugin)
        .run();

    Ok(())
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
fn android_main(app: bevy_android::android_activity::AndroidApp) {
    disable_touch_sounds(&app);
    let _ = bevy_android::ANDROID_APP.set(app);
    run().ok();
}

/// Suppresses Android system "Touch sounds" that play on every touch
/// interaction. Calls `setSoundEffectsEnabled(false)` on the Activity's
/// decor view through JNI.
#[cfg(target_os = "android")]
fn disable_touch_sounds(app: &bevy_android::android_activity::AndroidApp) {
    use jni::objects::JObject;
    use jni::refs::Cast;
    use jni::sys::jobject;
    use jni::{jni_sig, jni_str, JavaVM, JValue};

    let vm_ptr = app.vm_as_ptr();
    if vm_ptr.is_null() {
        return;
    }
    let vm = unsafe { JavaVM::from_raw(vm_ptr.cast()) };
    let _ = vm.attach_current_thread(|env| -> jni::errors::Result<()> {
        // SAFETY: activity reference is valid while `app` exists (unowned global ref)
        let activity_ptr = app.activity_as_ptr() as jobject;
        let activity = unsafe { Cast::<JObject>::from_raw(env, &activity_ptr)? };

        let window = env
            .call_method(
                &activity,
                jni_str!("getWindow"),
                jni_sig!("()Landroid/view/Window;"),
                &[],
            )?
            .l()?;
        let view = env
            .call_method(
                &window,
                jni_str!("getDecorView"),
                jni_sig!("()Landroid/view/View;"),
                &[],
            )?
            .l()?;
        env.call_method(
            &view,
            jni_str!("setSoundEffectsEnabled"),
            jni_sig!("(Z)V"),
            &[JValue::Bool(false)],
        )?;
        Ok(())
    });
}
