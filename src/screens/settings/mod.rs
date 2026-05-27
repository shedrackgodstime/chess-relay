//! Settings screen placeholder for presentation and control preferences.

use bevy::prelude::*;

use crate::screens::Screen;
use crate::theme::{palette, widgets};
use crate::ui::components::ScreenRoot;

/// Registers the settings screen plugin and its screen-local systems.
pub(super) struct SettingsPlugin;

#[derive(Component)]
struct BackButton;

impl Plugin for SettingsPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(Screen::Settings), spawn_settings)
            .add_systems(OnExit(Screen::Settings), despawn_settings)
            .add_systems(
                Update,
                handle_settings_actions.run_if(in_state(Screen::Settings)),
            );
    }
}

fn spawn_settings(mut commands: Commands) {
    commands
        .spawn((
            widgets::screen_root_node(),
            BackgroundColor(palette::APP_BACKGROUND),
            ScreenRoot,
        ))
        .with_children(|parent| {
            parent
                .spawn(widgets::panel_node(520.0))
                .with_children(|parent| {
                    parent.spawn(widgets::display_text("Settings"));
                    parent.spawn(widgets::body_text(
                        "This screen will hold camera, presentation, controls, and match preferences once the core game loop is rebuilt.",
                    ));
                    let back = widgets::button(parent, "Back Home", widgets::ButtonKind::Ghost);
                    parent.commands().entity(back).insert(BackButton);
                });
        });
}

fn despawn_settings(mut commands: Commands, roots: Query<Entity, With<ScreenRoot>>) {
    for entity in roots.iter() {
        commands
            .entity(entity)
            .despawn_related::<Children>()
            .despawn();
    }
}

fn handle_settings_actions(
    mut next_screen: ResMut<NextState<Screen>>,
    query: Query<&Interaction, (Changed<Interaction>, With<BackButton>)>,
) {
    for interaction in query.iter() {
        if *interaction == Interaction::Pressed {
            next_screen.set(Screen::Home);
        }
    }
}
