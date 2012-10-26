Mimic  is the "Mini Mailslot Internal Communicator"

Is a very lightweight chat client for use on a LAN that uses Windows mailslots instead of sockets.


Configuration:

Mimic is a click-and-run application--it doesn't require installation on your machine. There are, however, a couple of configuration options that should be set.

Starting the application and click "Tools > Options" on the menu bar to set these two options.

"Recipient" is the name of the computer to which messages will be sent. This may be the network name of a computer, which will send messages only to that machine; It may be a "*" to put the application into broadcast mode, which will send messages to all computers in the domain that are running mimic; or it may be a "." to put the application in loopback mode, which will send messages to itself.

"Nick" is a nickname that will precede all your transmissions.  This is a convenience for the users, particularly when using broadcast mode, but the application does not attempt to ensure that each user selects a unique name.

Operation:

Mimic works like many other chat clients: Type a message in the box at the bottom of the window and press "Enter" to send the message.

In normal operation mimic can be minimized and will pop-up when a message is received.  If you do not want the application to pop up, you can select "Tools > Stealth Mode" on the menu.  If a message is received while in stealth mode, a red box will appear around the mimic icon in the system tray. To restore mimic and read the message, double-click the system tray icon.


Special Commands:

Typing "/ping" will cause the remote machine to send an automated reply.  Nothing will appear on the remote user's screen.  


How it works:

Mimic communicates by opening a "mailslot" on the local machine and sending datagrams to mailslots on remote machines.