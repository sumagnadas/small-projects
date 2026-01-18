.intel_syntax noprefix
.global _start

exit:
	mov rax, 60
	syscall
	ret # just for the sake of it
socket:
	mov rax, 41
	syscall
	ret

bind:
	mov rax, 49
	syscall
	ret
listen:
	mov rax, 50
	syscall
	ret
accept:
	mov rax, 43
	syscall
	ret
open:
	mov rax, 2
	syscall
	ret
write:
	mov rax, 1
	syscall
	ret
close:
	mov rax, 3
	syscall
	ret
read:
	mov rax, 0
	syscall
	ret
_start:
	# create a socket
	mov rdi, 2
	mov rsi, 1
	mov rdx, 0
	call socket 

	### Even though stack grows downwards,
	### data writing and reading is always done
	### from lower addresses to higher addresses.

	### Data structure as local variables on stack
	#         [rsp-8]              => socket fd
	#         [rsp-25] -> [rsp-9]  => sockaddr object
	# (later) [rsp-26]             => new connection fd
	# (later) [rsp-47] -> [rsp-27] => response string

	# creating the sockaddr object on stack
	push rbp
	mov rbp, rsp
	sub rbp, 8
	sub rsp, 25 # 16 for sockaddr + 8 for the initial offset

	mov byte ptr [rbp], al # store the fd on the stack
	# sockaddr object
	mov word ptr [rbp-16], 0x0002      # sin_family
	mov word ptr [rbp-14], 0x5000      # sin_port
	mov dword ptr [rbp-12], 0x00000000 # sin_addr

	# bind the socket
	mov dil, byte ptr [rbp]  # move the socket fd to rdi
	lea rsi, [rbp-16]
	mov rdx, 16
	call bind

	# listen on the bound port
	mov dil, byte ptr [rbp]
	mov rsi, 0
	call listen

	# accept incoming connections
	mov dil, byte ptr [rbp]
	mov rsi, 0
	mov rdx, 0
	call accept

	# store the fd for the connection
	sub rsp, 1
	mov byte ptr [rbp-17], al

	# read the request
	mov dil, [rbp-17]
	lea rsi, [rbp-37-256] # have to read the new request to some valid memory to make it work, cant store it to null
	mov rdx, 256
	call read

	# send a static response
	# the string is written backwards to account for endian-ness
	# also we cant directly write a qword to memory; we have to use an intermediate register.
	sub rsp, 20 # local var for the string "HTTP/1.0 200 OK\r\n\r\n"
	mov rax, 0x302e312f50545448
	mov qword ptr [rbp-37], rax
	mov rax, 0x0d4b4f2030303220
	mov qword ptr [rbp-29], rax
	mov dword ptr [rbp-21], 0x000a0d0a

	mov dil, byte ptr [rbp-17]
	lea rsi, [rbp-37]
	mov rdx, 19
	call write

	# close the conenction after sending the response
	mov dil, byte ptr [rbp-17]
	call close

	# return the stack to previous point
	add rbp, 8
	mov rsp, rbp
	pop rbp

	# exit the program
	mov rdi, 0
	call exit
