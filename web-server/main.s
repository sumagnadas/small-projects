.intel_syntax noprefix
.global _start

exit:
        mov rax, 60
        syscall
        ret # just for the sake of it
_start:
        call exit
