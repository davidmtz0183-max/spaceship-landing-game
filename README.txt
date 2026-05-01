PLAY THE GAME HERE!! https://davidmtz0183.itch.io/spaceship-landing-simulator

Planet Landing Simulator

This is my physics engine game project. I made it as a simple top-down space landing game in Godot.

How to play:
- Press Enter or Space to start
- A / D or Left / Right arrows rotate the ship
- W / Up arrow / Space turns on thrust
- S / Down arrow slows the ship slightly
- R restarts after a crash or landing
- Esc quits

Goal:
Land the ship on the green landing pad on the planet. The landing only counts if the ship is moving slowly enough and is at a safe angle. If the ship hits the planet too fast, misses the landing pad, or falls into the black hole, it crashes.

Physics concepts used:
1. Kinematics:
The ship has position, velocity, acceleration, speed, and time. The position is updated every frame based on velocity.

2. Newton's Laws / Forces:
The thrust from the ship acts like an applied force that changes acceleration. Gravity from the planet and the black hole also changes acceleration.

3. Momentum / Collisions:
The ship keeps moving because of its velocity, and the landing/crash check depends on the ship's speed and direction when it collides with the planet.

I kept the graphics simple because the main point of the project is the physics behavior. The HUD shows speed, altitude, acceleration, fuel, time, and score so it is easier to see what is happening while playing.


Leaderboard update:
This version saves the top 5 scores locally on the computer. After a high score, the player enters a 3-character name like an arcade machine. Use letters on the keyboard or the arrow keys to change/select letters, then press Enter to save.
