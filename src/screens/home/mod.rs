//! Home screen for top-level product navigation.

use bevy::prelude::*;

use super::game::PendingMatchPresentation;
use crate::screens::Screen;
use crate::theme::{palette, spacing, widgets};
use crate::ui::components::ScreenRoot;
use crate::ui::rasterize::rasterize_svg;

/// Registers the home screen plugin and its screen-local systems.
pub(super) struct HomePlugin;

#[derive(Component)]
struct SameDeviceButton;

#[derive(Component)]
struct OnlineGameButton;

#[derive(Component)]
struct ComputerGameButton;

#[derive(Component)]
struct SettingsButton;

#[derive(Resource)]
struct HomeVisuals {
    settings: Handle<Image>,
}

impl FromWorld for HomeVisuals {
    fn from_world(world: &mut World) -> Self {
        let mut images = world.resource_mut::<Assets<Image>>();

        Self {
            settings: images.add(rasterize_svg(include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/assets/ui/icons/settings.svg"
            )))),
        }
    }
}

impl Plugin for HomePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<HomeVisuals>()
            .add_systems(OnEnter(Screen::Home), spawn_home)
            .add_systems(OnExit(Screen::Home), despawn_home)
            .add_systems(Update, handle_home_actions.run_if(in_state(Screen::Home)));
    }
}

fn spawn_home(mut commands: Commands, asset_server: Res<AssetServer>, visuals: Res<HomeVisuals>) {
    commands
        .spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                flex_direction: FlexDirection::Column,
                justify_content: JustifyContent::SpaceBetween,
                align_items: AlignItems::Center,
                ..default()
            },
            BackgroundColor(Color::BLACK),
            ScreenRoot,
        ))
        .with_children(|parent| {
            parent.spawn((
                Node {
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    position_type: PositionType::Absolute,
                    left: Val::Px(0.0),
                    top: Val::Px(0.0),
                    ..default()
                },
                ImageNode::new(asset_server.load("home-bg.jpeg")),
            ));

            parent.spawn((
                Node {
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    position_type: PositionType::Absolute,
                    left: Val::Px(0.0),
                    top: Val::Px(0.0),
                    ..default()
                },
                BackgroundColor(Color::srgba(0.01, 0.015, 0.02, 0.82)),
            ));

            let logo_font: Handle<Font> = asset_server.load("fonts/Cinzel-Bold.ttf");
            parent
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        justify_content: JustifyContent::Center,
                        align_items: AlignItems::FlexStart,
                        padding: UiRect::axes(Val::Px(spacing::LARGE), Val::Px(spacing::XLARGE)),
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    parent
                        .spawn((
                            Node {
                                width: Val::Auto,
                                height: Val::Auto,
                                ..default()
                            },
                            BackgroundColor(Color::NONE),
                        ))
                        .with_children(|parent| {
                            parent.spawn((
                                Text::new("Chess\nRelay"),
                                TextFont {
                                    font: logo_font.clone(),
                                    font_size: 70.0,
                                    ..default()
                                },
                                TextColor(Color::srgb(0.05, 0.04, 0.02)),
                                Node {
                                    position_type: PositionType::Absolute,
                                    left: Val::Px(2.0),
                                    top: Val::Px(2.0),
                                    ..default()
                                },
                            ));
                            parent.spawn((
                                Text::new("Chess\nRelay"),
                                TextFont {
                                    font: logo_font,
                                    font_size: 70.0,
                                    ..default()
                                },
                                TextColor(palette::ACCENT),
                            ));
                        });
                });

            parent
                .spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        right: Val::Px(spacing::LARGE),
                        top: Val::Px(spacing::XLARGE),
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    let settings = corner_icon_button(parent, visuals.settings.clone());
                    parent.commands().entity(settings).insert(SettingsButton);
                });

            parent.spawn(Node {
                flex_grow: 1.0,
                ..default()
            });

            parent
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        justify_content: JustifyContent::Center,
                        padding: UiRect::bottom(Val::Px(36.0)),
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    parent
                        .spawn((
                            Node {
                                width: Val::Px(420.0),
                                max_width: Val::Percent(92.0),
                                flex_direction: FlexDirection::Column,
                                row_gap: Val::Px(12.0),
                                ..default()
                            },
                            BackgroundColor(Color::NONE),
                        ))
                        .with_children(|parent| {
                            let online = mode_button(
                                parent,
                                "Online Multiplayer",
                                widgets::ButtonKind::Primary,
                            );
                            parent.commands().entity(online).insert(OnlineGameButton);

                            let same_device =
                                mode_button(parent, "Same Device", widgets::ButtonKind::Secondary);
                            parent
                                .commands()
                                .entity(same_device)
                                .insert(SameDeviceButton);

                            let computer = mode_button(
                                parent,
                                "Play Computer",
                                widgets::ButtonKind::Secondary,
                            );
                            parent
                                .commands()
                                .entity(computer)
                                .insert(ComputerGameButton);
                        });
                });
        });
}

fn despawn_home(mut commands: Commands, roots: Query<Entity, With<ScreenRoot>>) {
    for entity in roots.iter() {
        commands
            .entity(entity)
            .despawn_related::<Children>()
            .despawn();
    }
}

#[allow(clippy::type_complexity)]
fn handle_home_actions(
    mut commands: Commands,
    mut next_screen: ResMut<NextState<Screen>>,
    query: Query<(Entity, &Interaction), (Changed<Interaction>, With<Button>)>,
    same_device_buttons: Query<(), With<SameDeviceButton>>,
    online_buttons: Query<(), With<OnlineGameButton>>,
    computer_buttons: Query<(), With<ComputerGameButton>>,
    settings_buttons: Query<(), With<SettingsButton>>,
) {
    for (entity, interaction) in query.iter() {
        if *interaction != Interaction::Pressed {
            continue;
        }

        if same_device_buttons.get(entity).is_ok() {
            commands.insert_resource(PendingMatchPresentation::same_device("Local Rival"));
            next_screen.set(Screen::Game);
        } else if computer_buttons.get(entity).is_ok() {
            commands.insert_resource(PendingMatchPresentation::computer("Anton Bot"));
            next_screen.set(Screen::Game);
        } else if online_buttons.get(entity).is_ok() {
            commands.insert_resource(PendingMatchPresentation::online("Anton", true));
            next_screen.set(Screen::Lobby);
        } else if settings_buttons.get(entity).is_ok() {
            next_screen.set(Screen::Settings);
        }
    }
}

fn mode_button(
    parent: &mut ChildSpawnerCommands,
    label: &str,
    kind: widgets::ButtonKind,
) -> Entity {
    let button = widgets::button(parent, label, kind);
    parent.commands().entity(button).insert(Node {
        width: Val::Percent(100.0),
        min_height: Val::Px(64.0),
        padding: UiRect::axes(Val::Px(18.0), Val::Px(10.0)),
        justify_content: JustifyContent::Center,
        align_items: AlignItems::Center,
        border: UiRect::all(Val::Px(1.0)),
        border_radius: BorderRadius::all(Val::Px(20.0)),
        ..default()
    });
    button
}

fn corner_icon_button(parent: &mut ChildSpawnerCommands, icon: Handle<Image>) -> Entity {
    parent
        .spawn((
            Node {
                width: Val::Px(52.0),
                height: Val::Px(52.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                border: UiRect::all(Val::Px(1.0)),
                border_radius: BorderRadius::all(Val::Px(18.0)),
                ..default()
            },
            Button,
            BackgroundColor(Color::srgba(0.05, 0.06, 0.08, 0.72)),
            BorderColor::all(Color::srgba(0.72, 0.60, 0.39, 0.22)),
        ))
        .with_child((
            Node {
                width: Val::Px(22.0),
                height: Val::Px(22.0),
                ..default()
            },
            ImageNode::new(icon),
        ))
        .id()
}
