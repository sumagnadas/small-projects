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
_start:
	# create a socket
	mov rdi, 2
	mov rsi, 1
	mov rdx, 0
	call socket 

	# creating the sockaddr object on stack
	push rbp
	mov rbp, rsp
	sub rbp, 8
	sub rsp, 25 # 16 for sockaddr + 8 for the initial offset
	
	mov byte ptr [rbp], al # store the fd on the stack
	# sockaddr object
	mov word ptr [rbp+1], 0x0002        # sin_family
	mov word ptr [rbp+3], 0x5000      # sin_port
	mov dword ptr [rbp+5], 0x00000000 # sin_addr
	
	# bind the socket
	mov dil, byte ptr [rbp]  # move the socket fd to rdi
	lea rsi, [rbp+1]
	mov rdx, 16
	call bind
	
	# listen on the bound port
	mov dil, byte ptr [rbp]
	mov rsi, 0
	call listen

	# return the stack to previous point
	add rbp, 8
	mov rsp, rbp
	pop rbp
	
	# exit the program
	mov rdi, 0
	call exit
