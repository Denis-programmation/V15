	.file	"cpm.S"
	.option pic
	.attribute arch, "rv64i2p1_m2p0_a2p1_f2p2_d2p2_c2p0_zicsr2p0_zifencei2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16

#    .include "system.def"

    .global main
    
    .text

    .equ    NUMBER_OF_DIR_ENTRIES, 128  # = 2 blocs
    .equ    NUMBER_OF_DATA_BLOCKS, 398  # = 400 - les 2 du répertoire
    .equ    BLOCK_SIZE, 2048            # unité d'allocation indivisible
    .equ    DIRECTORY_SIZE, 32
    
.macro  push   Xa
    ADDI	sp, sp, -8
    SD		\Xa, (sp)
.endm

.macro  pop   Xa
	LD		\Xa, (sp)
    ADDI	sp, sp, 8
.endm

main:
    LA      a0, COMMANDE
    CALL    printf
    LW      t0, FIRST_GETCHAR
    BNEZ    t0, GETCHAR
M1:
    CALL    getchar                     # empty input buffer
    LI      t0, 0x0A
    BNE     a0, t0, M1
GETCHAR:
    SW      zero, FIRST_GETCHAR, t1     # clear first getchar
    CALL    getchar                     # get 1 char from keyboard
    BEQ     a0, t0, GETCHAR
    LI      t0, 0x31
    BNE     a0, t0, M10
    CALL    FORMAT_DISK
    J       M90
    
M10:
    LI      t0, 0x32
    BNE     a0, t0, M20
    CALL    READ_DIRECTORY
    J       M90
    
M20:
    LI      t0, 0x33
    BNE     a0, t0, M90
# export
    LA      a0, COMMANDE2
    CALL    printf
    LA      s0, FILE_TO_FETCH
    LA      s1, FILE_TO_FETCH2
    LI      s2, 11
    LI      s3, 0x20
M30:
    SB      s3, (s1)
    ADDI    s2, s2, -1
    ADDI    s1, s1, 1
    BNEZ    s2, M30                     # write 11 blank chars
    LA      s1, FILE_TO_FETCH2
    LI      s2, 12
    LI      s3, 0x0A
M31:
    CALL    getchar                     # empty input buffer
    BNE     a0, s3, M31                 # fin de ligne ?
GETCHAR2:
    CALL    getchar
    CALL    toupper
    SB      a0, (s0)
    SB      a0, (s1)
    ADDI    s0, s0, 1
    ADDI    s1, s1, 1
    ADDI    s2, s2, -1                  # compteur de boucle
    LI      s4, 0x2E                    # point
    BEQ     a0, s4, DOT                 # point ?
    BEQ     a0, s3, END1                # 0x0a ?
    BEQZ    s2, END2                    # max 12 characters (FFFFFFFF.TTT)
    J       GETCHAR2
    
DOT:
    ADDI    s1, s1, -1                  # on va effacer le point en le remplaçant par un blanc
    LI      s4, 0x20
    SB      s4, (s1)
    LA      s1, FILE_TO_FETCH2
    ADDI    s1, s1, 8                   # first char of filetype
    J       GETCHAR2
    
END1:
    ADDI    s1, s1, -1
    LI      s4, 0x20
    SB      s4, (s1)
    ADDI    s1, s1, 1
    SB      s4, (s1)                    # replace 0x0a by space
    ADDI    s0, s0, -1
    SB      zero, (s0)                  # replace 0x0a by 0x00
END2:
    LA      a0, debug
    LA      a1, FILE_TO_FETCH
    LA      a2, FILE_TO_FETCH2
    CALL    printf
    CALL    FETCH_FILE
M90:
    J       main

#   CALL    fcloseall

CREATE_DISK_IMAGE:
    push    ra
    LA      a0, DISK_IMAGE
    LA      a1, CREATE_OPTION
    CALL    fopen
    SD      a0, FID_CPM, t0             # file pointer
    CALL    __errno_location
    LD      a0, (a0)                    # a0 = address of ERRNO
    BEQZ    a0, CDI
    LA      a0, MSG3
    LA      a1, DISK_IMAGE
    CALL    printf
    J       ABEND
    
CDI:
    pop     ra
    RET    

WRITE_DISK_IMAGE:                       # in : a0 = address of buffer, a1 = element length, a2 = number of elements
    push    ra
    push    s0
    LD      a3, FID_CPM                 # file pointer
    MV      s0, a2                      # sauvegarder nb éléments à écrire
    CALL    fwrite
    BEQ     a0, s0, WDI                 # nb éléments écrits
    LA      a0, MSG4
    LA      a1, DISK_IMAGE
    CALL    printf
    J       ABEND
    
WDI:
    pop     s0
    pop     ra
    RET

READ_DISK_IMAGE:                        # in : a0 = address of buffer, a1 = element length, a2 = number of elements
    push    ra
    push    s0
    LD      a3, FID_CPM                 # file pointer
    MV      s0, a2
    CALL    fread
    BEQ     a0, s0, RDI                 # number of elements to write
    LA      a0, MSG6
    LA      a1, DISK_IMAGE
    CALL    printf
    J       ABEND
    
RDI:
    pop     s0
    pop     ra
    RET

POSITION_DISK_IMAGE:                    # in : a1 = offset depuis le début du fichier
    push    ra
    LD      a0, FID_CPM                 # file pointer
    MV      a2, zero                    # SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2
    CALL    fseek
    BEQZ    a0, PDI
    LA      a0, MSG7
    LA      a1, DISK_IMAGE
    CALL    printf
    J       ABEND
    
PDI:
    pop     ra
    RET

CLOSE_DISK_IMAGE:
    push    ra
    LD      a0, FID_CPM                 # file pointer
    CALL    fclose
    BEQZ    a0, LDI
    LA      a0, MSG5
    LA      a1, DISK_IMAGE
    CALL    printf
    J       ABEND
    
LDI:
    SD      zero, FID_CPM, t0
    pop     ra
    RET    
    
FORMAT_DISK:
    push    ra
    push    s0
# create file
    CALL    CREATE_DISK_IMAGE
# write directory entries
# dans CP/M toute la zone des répertoires est remplie de E5, mais je préfère écrire une trame de répertoire à la place
# t = fwrite ( str, len, 1, fp);
    LI      s0, NUMBER_OF_DIR_ENTRIES
FD1:
    LA      a0, DIRECTORY               # string to write
    LI      a1, DIRECTORY_SIZE          # element length
    LI      a2, 1                       # number of elements
    CALL    WRITE_DISK_IMAGE
    ADDI    s0, s0, -1
    BNEZ    s0, FD1
# initialize data blocks (comme dans CP/M)
    LI      s0, NUMBER_OF_DATA_BLOCKS
FD2:
    LA      a0, E5
    LI      a1, BLOCK_SIZE
    LI      a2, 1
    CALL    WRITE_DISK_IMAGE
    ADDI    s0, s0, -1
    BNEZ    s0, FD2
    CALL    CLOSE_DISK_IMAGE
    pop     s0
    pop     ra
    RET

OPEN_DISK_IMAGE:
    push    ra
    LD      a0, FID_CPM
    BNEZ    a0, ODI_DONE
    LA      a0, DISK_IMAGE
    LA      a1, READ_OPTION
    CALL    fopen
    SD      a0, FID_CPM, t0
    CALL    __errno_location
    LD      a0, (a0)                    # a0 = address of ERRNO
    BEQZ    a0, ODI_DONE
    LA      a0, MSG2
    LA      a1, DISK_IMAGE
    CALL    printf
    J       ABEND
    
ODI_DONE:
    pop     ra
    RET    

READ_DIRECTORY:
/* La FAT est une bitmap, c'est-à-dire 1 bit par bloc (unité d'allocation).
   Pour simplifier : je suppose que toutes les entrées de répertoire d'un même fichier se suivent
    et qu'il n'y a pas une autre qui traine plus loin, ce qui pourrait arriver si la disquette a déjà beaucoup travaillé */
    push    ra
    push    s0      # BLOCK_COUNTER
    push    s1      # SECTOR_COUNTER
    push    s2      # A2
    push    s3      # A3
    push    s4      # MD3 = D3 du 68000
    push    s5      # MD4 = D4
    push    s6      # FILESIZE
    CALL    OPEN_DISK_IMAGE
    MV      a1, zero                    # remettre au début du fichier
    CALL    POSITION_DISK_IMAGE
    LA      a0, DIR_BUFFER
    LI      a1, DIRECTORY_SIZE*NUMBER_OF_DIR_ENTRIES
    LI      a2, 1
    CALL    READ_DISK_IMAGE
# all directories are now read
# on va recenser tous les blocs alloués et renseigner la bitmap
    MV      s0, zero                    # allocated blocks counter
    MV      s1, zero                    # sectors counter
    LA      s2, DIR_BUFFER
    LI      s4, NUMBER_OF_DIR_ENTRIES   # MD3
LOOP2:
    LBU     t0, (s2)
    LI      t1, 0xE5
    BEQ     t0, t1, CONTINUE            # unused dir entryt0, s2, s5
# afficher nom et taille
    LBU     t0, 12(s2)
    BNEZ    t0, NOT_FIRST_ENTRY
    MV      s3, s2
    ADDI    s3, s3, 1
    LI      s5, 8                       # MOV     MD4, #8
LOOP21:
    LBU     a0, (s3)
    ADDI    s3, s3, 1
    LI      t0, 0x20                    # space
    BEQ     a0, t0, SKP1
    CALL    putchar
SKP1: 
    ADDI    s5, s5, -1                  # SUBS    MD4, MD4, 1
    BNEZ    s5, LOOP21
    LI      a0, 0x2E                    # dot
    CALL    putchar
    LI      s5, 3                       # MOV     MD4, 3
LOOP22:
    LBU     a0, (s3)
    ADDI    s3, s3, 1
    LI      t0, 0x20
    BEQ     a0, t0, SKP2
    CALL    putchar
SKP2:
    ADDI    s5, s5, -1                  # SUBS    MD4, MD4, 1
    BNEZ    s5, LOOP22
    LI      a0, 0x20                    # space
    CALL    putchar
    MV      s6, zero
NOT_FIRST_ENTRY:
    LBU     a0, DIRECTORY_SIZE(s2)
    LI      t0, 0xE5
    BEQ     a0, t0, LAST_ENTRY
    LBU     a0, DIRECTORY_SIZE+12(s2)   # si Xt de l'entrée suivante = 0
    BEQZ    a0, LAST_ENTRY
    LBU     a0, 15(s2)                  # LDRB    W0, [A2, 15]        number of sectors
    ADD     s6, s6, a0                  # ADD     FILESIZE, FILESIZE, W0
    ADD     s1, s1, a0                  # ADD     SECTOR_COUNTER, SECTOR_COUNTER, W0
    J       FILL_FAT
    
LAST_ENTRY:
    LBU     a0, 15(s2)                  # LDRB    W0, [A2, 15]        number of sectors
    ADD     s6, s6, a0                  # FILESIZE, FILESIZE, W0
    ADD     s1, s1, a0                  # ADD SECTOR_COUNTER, SECTOR_COUNTER, W0
    LA      a0, TAILLE
    MV      a1, s6                      # FILESIZE
    CALL    printf
# renseigner la FAT
FILL_FAT:
    LA      s3, FAT
    LI      s5, 16                      # MOV     MD4, 16
LOOP3:
    ADD     t0, s2, s5
    LHU     a0, (t0)                    # LDRH    W0, [A2, MD4]
    BEQZ    a0, RIEN_A_FAIRE
# the FAT is a bitmap : divide D5 by 8 gives the byte address and the remainder (modulo 8) the bit to set
# en version ARM, je vais le faire avec des AND et LSR
    ANDI    a1, a0, 7                   # = le reste de la division
    SRLI    a2, a0, 3                   # = le quotient
    LI      a3, 1
    SLL     a3, a3, a1                  # masque : 1 shifted left
    ADD     t0, s3, a2                  # addition des adresses car pas d'adressage base+index
    LBU     t1, (t0)
    OR      t1, t1, a3
    SB      t1, (t0)
    ADDI    s0, s0, 1                   # ADD     BLOCK_COUNTER, BLOCK_COUNTER, #1
RIEN_A_FAIRE:
    ADDI    s5, s5, 2                   # ADD     MD4, MD4, #2
    LI      t0, 32
    BLT     s5, t0, LOOP3
CONTINUE:
    ADDI    s2, s2, DIRECTORY_SIZE      # ADD     A2, A2, #DIRECTORY_SIZE
    ADDI    s4, s4, -1                  # SUBS    MD3, MD3, #1
    BNEZ    s4, LOOP2
# affichage de l'espace occupé
    LA      a0, TOTAL_BLOCKS
    MV      a1, s0                      # BLOCK_COUNTER
    CALL    printf
    LA      a0, TOTAL_SECTORS
    MV      a1, s1                      # SECTOR_COUNTER
    CALL    printf
    pop     s6
    pop     s5
    pop     s4
    pop     s3
    pop     s2
    pop     s1
    pop     s0
    pop     ra
    RET

CREATE_OUTPUT_FILE:             # in : a0 = address of filename - out : a0 = 0 if success
    push    ra
    LA      a1, CREATE_OPTION   # "w+"
    CALL    fopen
    SD      a0, FID_EXP, t0     # file pointer
    CALL    __errno_location
    LD      a0, (a0)                    # a0 = address of ERRNO
    BEQZ    a0, COF
    LA      a0, MSG1
    LA      a1, FILE_TO_FETCH
    CALL    printf
    J       ABEND
    
COF:
    pop     ra
    RET

WRITE_OUTPUT_FILE:              # in : a1 = size
    push    ra
    push    s0
    LA      a0, BLOCK_BUFFER
    LI      a2, 1               # 1 element to write
    LD      a3, FID_EXP         # file pointer
    MV      s0, a2
    CALL    fwrite
    BEQ     a0, s0, WOF         # a0 = nb elements written
    LA      a0, MSG8
    LA      a1, FILE_TO_FETCH
    CALL    printf
    J       ABEND
    
WOF:
    pop     s0
    pop     ra
    RET

CLOSE_OUTPUT_FILE:
    push    ra
    LD      a0, FID_EXP         # file pointer
    CALL    fclose
    BEQZ    a0, LOF
    LA      a0, MSG9
    LA      a1, FILE_TO_FETCH
    CALL    printf
    J       ABEND
    
LOF:
    pop     ra
    RET    

/*
    s0 = NUM_SECT_TO_READ
    s1 = NUM_SECTORS_READ
    s2 = ENTRY_NUMBER
    s3 = STOP
*/

EXPORT_BLOCK:                   # in : a0 = numéro de bloc à exporter (on démarre à 2, après le répertoire)
    push    ra
    LI      t0, BLOCK_SIZE
    SLLI    a1, a0, 11          # a1 = numéro de bloc multiplié par 2048
    CALL    POSITION_DISK_IMAGE
    LA      a0, BLOCK_BUFFER
    LI      a1, BLOCK_SIZE
    LI      a2, 1
    CALL    READ_DISK_IMAGE     # in : X0 = address of buffer, X1 = element length, X2 = number of elements
    ADDI    s1, s1, 16          # NUM_SECTORS_READ, NUM_SECTORS_READ, #16
# write block to output (export) file
    LI      a1, BLOCK_SIZE
    MV      s3, zero            # MOV     STOP, XZR
    BLE     s1, s0, .WRITE_ALL  # not too much read
# de combien de secteurs faut-il raccourcir ?
dbug:
    LI      s3, 1               # MOV     STOP, #1
    SUB     t0, s1, s0          # SUB     W0, NUM_SECTORS_READ, NUM_SECT_TO_READ   nombre de secteurs à tronquer
    SLLI    t0, t0, 7           # t0 * 128, converti en nombre d'octets
    LI      a1, BLOCK_SIZE
    SUB     a1, a1, t0          # w1 = block_size - (128*nb de sect à enlever) = 384 pour le 1er fichier
# recherche du ctrl-Z
    LA      t0, BLOCK_BUFFER    # adresse du début des données
.EB1:
    ADD     t2, t0, a1          # t2 = adresse du début de BLOCK_BUFFER + taille
    ADDI    t3, t2, -1          # t3 = adresse de l'octet à tester
    LBU     t4, (t3)
    LI      t5, 0x1A
    BNE     t4, t5, .WRITE_ALL  # si plus de control Z à la fin, on écrit ce qui reste dans le fichier de sortie
    ADDI    a1, a1, -1          # taille à écrire - 1
    J      .EB1
    
.WRITE_ALL:
    CALL    WRITE_OUTPUT_FILE
    pop     ra
    RET    

/*
    s0 = NUM_SECT_TO_READ
    s1 = NUM_SECTORS_READ
    s2 = ENTRY_NUMBER
    s3 = STOP
    s4 = sauvegarde de s11
    s5 = compteur de boucle
    s11 = pointeur vers DIR_BUFFER
*/

FETCH_FILE:
    push    ra
    MV      s0, zero                    # MOV     NUM_SECT_TO_READ, WZR
    MV      s1, zero                    # MOV     NUM_SECTORS_READ, WZR
    LA      a0, FILE_TO_FETCH
    CALL    CREATE_OUTPUT_FILE
    CALL    READ_DIRECTORY
    LA      s11, DIR_BUFFER
    MV      s2, zero                    # MOV     ENTRY_NUMBER, XZR            from 0 to number of dir entries
LOOP1:
    MV      s4, s11                     # sauver X11
    LA      t2, FILE_TO_FETCH2
    LBU     t0, (s11)                   # un caractère de la première ligne d'entrée de répertoire
    ADDI    s11, s11, 1                 # étant donné qu'il n'y a pas de post-incrémentation
    LI      t1, 0xE5                    # entrée libre ?
    BEQ     t0, t1, RIEN_A_FAIR
    LI      s5, 11                      # MOV     X25, #11
LOP2:
    LBU     t0, (s11)
    ADDI    s11, s11, 1                 # post-incrémentation
    LBU     t1, (t2)
    ADDI    t2, t2, 1                   # post-incrémentation
    BNE     t0, t1, RIEN_A_FAIR         # si pas de correspondance du nom de fichier recherché
    ADDI    s5, s5, -1                  # SUBS    X25, X25, #1
    BNEZ    s5, LOP2
# file found, get block numberst0
    LI      s5, 8                       # 8 block numbers
    ADDI    s11, s11, 3                 # pointer vers la taille (nombre de secteurs)
    LBU     t1, (s11)
    ADDI    s11, s11, 1
    ADD     s0, s0, t1                  # ADD     NUM_SECT_TO_READ, NUM_SECT_TO_READ, W0
LOP3:
    LHU     a0, (s11)
    ADDI    s11, s11, 2
    BEQZ    a0, NOT_ALLOCATED
    CALL    EXPORT_BLOCK
    BNEZ    s3, EXIT                    #     STOP, EXIT
NOT_ALLOCATED:
    ADDI    s5, s5, -1                  # SUBS    X25, X25, #1
    BNEZ    s5, LOP3
RIEN_A_FAIR:
    MV      s11, s4                     # restaurer pointeur vers entrée
    ADDI    s2, s2, 1                   # ADD     ENTRY_NUMBER, ENTRY_NUMBER, 1
    LI      t0, NUMBER_OF_DIR_ENTRIES
    BGE     s2, t0, EXIT
    ADDI    s11, s11, DIRECTORY_SIZE
    J       LOOP1
    
EXIT:
    CALL    CLOSE_OUTPUT_FILE
    pop     ra
    RET

ABEND:
    CALL    fcloseall
    LI      a7, 93                  # SYS_EXIT
    LI      a0, 1                   # exit_failure
    ECALL 

    .section .rodata
    
DISK_IMAGE:         .asciz  "cpmdisk.bin"
MSG1:               .asciz  "Erreur de création du fichier de sortie '%s'.\n"
MSG2:               .asciz  "Erreur de lecture de l'image de disquette '%s'.\n"
MSG3:               .asciz  "Erreur de création de l'image de disquette '%s'\n"
MSG4:               .asciz  "Erreur d'écriture de l'image de disquette '%s'\n"
MSG5:               .asciz  "Erreur de fermeture de l'image de disquette '%s'\n"
MSG6:               .asciz  "Erreur de lecture de l'image de disquette '%s'\n"
MSG7:               .asciz  "Erreur de positionnement de l'image de disquette '%s'\n"
MSG8:               .asciz  "Erreur d'écriture du fichier exporté '%s'\n"
MSG9:               .asciz  "Erreur de fermeture du fichier exporté '%s'\n"
FORMAT_DONE:        .asciz  "Formatage effectué\n"
COMMANDE:           .asciz  "Commande ? 1=format, 2=dir, 3=export file : "
COMMANDE2:          .asciz  "Nom du fichier à exporter : "
REPERTOIRE:         .asciz  "Répertoire :\n"
TAILLE:             .asciz  " %d secteurs (de 128 octets)\n"
TOTAL_BLOCKS:       .asciz  "Nombre de blocs alloués %d sur 498\n"
TOTAL_SECTORS:      .asciz  "Nombre de secteurs alloués %d sur 6368\n"
CREATE_OPTION:      .asciz  "w+"
READ_OPTION:        .asciz  "r+"

# directory entry
# inspired by CP/M which is little endian
# Us Fn Fn Fn Fn Fn Fn Fn Fn Ty Ty Ty Xt At Lh Ll
# Al Al Al Al Al Al Al Al Al Al Al Al Al Al Al Al
DIRECTORY:  .byte   0xE5            # user number
FILENAME:   .space  8, 0x46         # file name
FILETYPE:   .space  3, 0x54         # file type
EXTEND:     .byte   0               # extend number (0 = no extend, 1 = extend n° 1...)
ATTRIBUTES: .byte   0               # attributes (saved, public, protected...)
TIMESTAMP:  .byte   0
FILELENGTH: .byte   0               # file length in sectors of 128 bytes
ALLOCATION: .space  16              # $0,$0,$0,$0,$0,$0,$0,$0  blocks allocated to the file, Al

    .data
    
FIRST_GETCHAR:      .word   1
FAT:                .space  NUMBER_OF_DATA_BLOCKS/8+1
FILE_TO_FETCH:      .asciz  "FFFFFFFF.TTT"
FILE_TO_FETCH2:     .asciz  "FFFFFFFFTTT?"
FID_CPM:            .dword  0
FID_EXP:            .dword  0
# initialized buffers
E5:         .space  BLOCK_SIZE, 0xE5

# debug messages
debug:      .asciz  "File to fetch '%s', file to fetch2 '%s'\n"

    .bss

# buffers
DIR_BUFFER:     .space  DIRECTORY_SIZE*NUMBER_OF_DIR_ENTRIES
BLOCK_BUFFER:   .space  BLOCK_SIZE

    .end
