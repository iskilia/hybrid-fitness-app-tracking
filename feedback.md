Feedback from using the simulator on my mac - categorised

Session tracking:
1. The app does not historically track the sessions correctly after I press the settings button. Once I start a session, finish it, return to the home screen, press the settings button, and then exit the settings, I would find that there are no sessions being tracked anymore even though I know that there are sessions I have tracked.
2. When I abandon a session, it should not count towards the number of sessions shown on the home screen.

Routines:
1. When I create a routine, I can't add exercises to the routine - at least visibly does not appear on the screen.
2. On the create a routine screen, it shows the "Start" button at the bottom, which then leads to starting an empty routine. The ideal flow should be to instead press "Create" at the end of creating a routine and then go back to the routines screen.
3. When looking through the default exercises, it is missing "Run" as an option.

Settings:
1. Let's remove the export functionality and refreshing the LLM Snapshot - it feels clunky in the settings.
2. Don't allow user to enter their bodyweight in the application.
3. Add textbox that allows the users to enternumber of megabytes that their data can take on the phone. Only accept whole numbers. Do not exceed 500. Default value is 10.

Data handling:
We missed the functionality for users to be able to dictate how much memory should the data/schema of this application should hold. We must respect this limit on every action that adds or removes data to the database. This would include:
1. Logging a session
2. Creating a routine
3. Creating a custom exercise.