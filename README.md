# Velocity Heat

An open-world street racing game that runs in the browser. It's built to stay smooth on weak hardware.

You get a procedurally built city with a downtown core and a neon night skyline. Around it are a coastal highway ring, rolling countryside and a winding mountain pass. Cars run on a tire-based physics model, and there are rival racers, police pursuits at night, traffic, drifting and a garage.

## Play

The game is a static site with no build step, but it needs to be served over HTTP because it uses ES modules:

```bash
python3 -m http.server 8000
# or
npx serve .
```

Then open http://localhost:8000. GitHub Pages also works: enable Pages on this branch and open the site.

## Features

- **Open world.** A 9×9 grid city with procedural skyscrapers, lit windows and neon signs at night. A highway ring runs along the coast, there are hills, forests and beaches, and a mountain pass with hairpins and guard rails climbs to snowy peaks.
- **Vehicle physics.** Slip-angle tire model (simplified Pacejka curve), weight transfer under braking and acceleration, a friction circle (power oversteer, wheelspin), aero drag and downforce, and a power-limited engine with a gearbox (auto or manual). RWD and AWD drivetrains, plus hills, crests and jumps.
- **Drifting.** Start a slide with the handbrake or by tapping the brake mid-corner, then hold it with throttle and steering. Optional traction and stability assists keep it controllable on a keyboard. Turn them off in Settings for raw handling.
- **No damage, no dead stops.** Only big buildings block you. Trees, lamp posts and rails are scenery you drive straight through. Traffic gets knocked out of the way, and other racers or cops can only nudge you.
- **Events.** 9 events: circuits, sprints and drift trials across the city, highway and mountain pass, including night-only street races that pay 1.5×.
- **AI rivals.** They use the same physics as you, follow a racing line with a speed profile computed from the track, and get mild rubber-banding.
- **Police (night).** Speed past a patrol and a pursuit starts. Heat goes up to 5 stars with reinforcements. Lose them to collect a bounty, but stop near a cop and you're busted.
- **Garage.** 7 cars from a D-class tuner to an S-class hypercar, 3 upgrade tiers each for engine, handling and nitrous, and 12 paint colors.
- **Day and night cycle.** The sky, lighting, reflections, street lights, headlight beams and building windows all change with the time of day.
- **Effects.** Tire smoke, skid marks, nitrous flames, speed FOV, camera shake, a procedural synthwave soundtrack and synthesized engine audio for each engine layout.
- **Controllers.** Full gamepad support (analog throttle, brake and steering, rumble, menu navigation), plus keyboard and on-screen touch controls.

## Performance on weak hardware

- The quality tier is auto-detected. **Dynamic resolution** then adjusts the render scale continuously to hold the frame rate.
- Instancing is used everywhere (buildings, trees, lamps, skid marks), terrain and roads are chunked so off-screen parts are culled, and materials are Lambert/Phong only.
- Light pools and headlight beams are fake (decals), so there are no expensive real-time lights.
- There are no external assets: every texture, model and sound is generated at startup. The full simulation costs about 0.5 ms of CPU per frame.
- Settings let you choose quality, resolution scale, traffic density, time of day, assists, gearbox and units.

## Controls

| Action | Keyboard | Controller |
|---|---|---|
| Accelerate / Brake–Reverse | W / S (↑ / ↓) | RT / LT |
| Steer | A / D (← / →) | Left stick |
| Handbrake | Space | A |
| Nitrous | Shift / N | X or L3 |
| Camera | C | Y |
| Look back / around | B | R3 / Right stick |
| Start event | Enter / F | D-pad ↑ |
| Reset to road | R | Hold B |
| Manual shift | E / Q | RB / LB |
| Map | M | View |
| Skip day/night | T | Pause menu |
| Pause | Esc / P | Start |
