# Web Server in Assembly
---
This folder contains a basic web server written in assembly, as part of the pwn.college dojo "Playing with Programs". Apart from a coding exercise in assembly, this project is aimed at understanding how assembly code interacts with external peripherals as well as some intricacies of networking and it's protocols.

This very simple web server has the following capabilities:-
- Can respond to GET, POST requests.
- Concurrency by multiprocessing for handling multiple requests of different types, adding scalability (probably).
- Max request length: 500 (for both GET and POST).
- GET requests return the contents of the file requested as response.
- POST requests writes the content of the request to the filepath mentioned.

Topics learned or explored via this project :-
- Assembly and syscalls
- Process forking in Linux
- Networking concepts like sockets, ports