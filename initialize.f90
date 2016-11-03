! initialize.f90
! Sets up initial configuration for MD or MC
PROGRAM initialize

  USE, INTRINSIC :: iso_fortran_env, ONLY : input_unit, output_unit, error_unit, iostat_end, iostat_eor

  USE config_io_module,  ONLY : write_cnf_atoms, write_cnf_mols
  USE maths_module,      ONLY : lowercase
  USE initialize_module, ONLY : allocate_arrays, deallocate_arrays, &
       &                        initialize_positions_lattice, initialize_orientations_lattice, &
       &                        initialize_positions_random,  initialize_orientations_random, &
       &                        initialize_chain_lattice, initialize_chain_random, initialize_chain_velocities, &
       &                        initialize_velocities, initialize_angular_velocities, &
       &                        n, r, e, v, w

  IMPLICIT NONE

  ! Reads several variables and options from standard input using a namelist nml

  INTEGER            :: nc, ioerr
  REAL               :: temperature, inertia, density, box, bond
  LOGICAL            :: velocities, random_positions, random_orientations
  INTEGER            :: molecule_option
  CHARACTER(len=10)  :: molecules

  CHARACTER(len=7), PARAMETER :: filename = 'cnf.inp' ! Will be used as an input file for simulations
  INTEGER,          PARAMETER :: atoms = 0, linear = 1, nonlinear = 2, chain = 3

  NAMELIST /nml/ nc, n, temperature, inertia, density, bond, &
       &         velocities, molecules, random_positions, random_orientations

  ! Default values
  n                   = 0       ! nc takes precedence unless n is explicitly specified
  nc                  = 4       ! default is N = 4*(4**3) = 256 on a fcc lattice, a small system
  temperature         = 1.0     ! should lie in the liquid region for density > 0.7 or so
  inertia             = 1.0     ! only relevant for molecular systems
  density             = 0.75    ! should lie in the liquid region for temperature > 0.9 or so
  bond                = 1.0     ! only relevant for chains
  velocities          = .FALSE. ! by default, produce positions for MC simulations
  molecules           = 'atoms' ! Options are 'atoms', 'chain', 'linear', 'nonlinear'
  random_positions    = .FALSE. ! by default, arrange atoms on a lattice
  random_orientations = .FALSE. ! by default, use predetermined molecular orientations

  READ ( unit=input_unit, nml=nml, iostat=ioerr ) ! namelist input
  IF ( ioerr /= 0 ) THEN
     WRITE ( unit=error_unit, fmt='(a,i15)') 'Error reading namelist nml from standard input', ioerr
     IF ( ioerr == iostat_eor ) WRITE ( unit=error_unit, fmt='(a)') 'End of record'
     IF ( ioerr == iostat_end ) WRITE ( unit=error_unit, fmt='(a)') 'End of file'
     STOP 'Error in initialize'
  END IF

  IF ( n <= 0 ) THEN
     IF ( nc <= 0 ) THEN
        WRITE ( unit=error_unit, fmt='(a,2i15)') 'nc must be positive', nc
        STOP 'Error in initialize'
     ELSE
        WRITE ( unit=output_unit, fmt='(a,t40,i15)') 'nc = ', nc
        n = 4*nc**3 ! fcc lattice
        WRITE ( unit=output_unit, fmt='(a,t40,i15)') 'n = ', n
     END IF
  ELSE
     WRITE ( unit=output_unit, fmt='(a,t40,i15)') 'n = ', n
  END IF

  IF ( INDEX(lowercase(molecules), 'chain') /= 0 ) THEN
     molecule_option = chain
     WRITE ( unit=output_unit, fmt='(a)' ) 'Chain of atoms, no periodic boundaries'
  ELSE IF  ( INDEX(lowercase(molecules), 'nonlinear') /= 0 ) THEN
     molecule_option = nonlinear
     WRITE ( unit=output_unit, fmt='(a)' ) 'Nonlinear molecules, periodic boundaries'
  ELSE IF  ( INDEX(lowercase(molecules), 'linear') /= 0 ) THEN
     molecule_option = linear
     WRITE ( unit=output_unit, fmt='(a)' ) 'Linear molecules, periodic boundaries'
  ELSE IF  ( INDEX(lowercase(molecules), 'atoms') /= 0 ) THEN
     molecule_option = atoms
     WRITE ( unit=output_unit, fmt='(a)' ) 'Atoms, periodic boundaries'
  ELSE
     WRITE ( unit=error_unit, fmt='(a,a)') 'Unrecognized molecules option: ', molecules
     STOP 'Error in initialize'
  END IF

  CALL allocate_arrays ( quaternions = ( molecule_option == nonlinear ) )

  CALL RANDOM_SEED()

  SELECT CASE ( molecule_option)

  CASE ( chain )

     IF ( random_positions ) THEN
        WRITE ( unit=output_unit, fmt='(a)' ) 'Chain, bonds randomly oriented, avoiding overlaps'
        CALL initialize_chain_random ! unit bond length
     ELSE
        WRITE ( unit=output_unit, fmt='(a)' ) 'Chain, close-packed atoms surrounded by vacuum'
        CALL initialize_chain_lattice ! unit bond length
     END IF
     IF ( velocities ) THEN
        WRITE ( unit=output_unit, fmt='(a,t40,f15.5)' ) 'Chain velocities at temperature', temperature
        CALL initialize_chain_velocities ( temperature )
     END IF

  CASE default

     IF ( random_positions ) THEN ! coordinates chosen randomly
        WRITE ( unit=output_unit, fmt='(a)' ) 'Random positions, avoiding overlaps'
        CALL initialize_positions_random ! unit box
     ELSE ! close packed lattice
        WRITE ( unit=output_unit, fmt='(a)' ) 'Close-packed lattice positions'
        CALL initialize_positions_lattice ! unit box
     END IF
     IF ( velocities ) THEN
        WRITE ( unit=output_unit, fmt='(a,t40,f15.5)' ) 'Velocities at temperature', temperature
        CALL initialize_velocities ( temperature )
     END IF

  END SELECT

  SELECT CASE ( molecule_option )

  CASE ( linear, nonlinear )
     IF ( random_orientations ) THEN
        WRITE ( unit=output_unit, fmt='(a)' ) 'Random orientations'
        CALL initialize_orientations_random
     ELSE
        WRITE ( unit=output_unit, fmt='(a)' ) 'Regular lattice of orientations'
        CALL initialize_orientations_lattice
     END IF

     IF ( velocities ) THEN
        WRITE ( unit=output_unit, fmt='(a,t40,2f15.5)' ) 'Angular velocities at temperature, inertia', temperature, inertia
        CALL initialize_angular_velocities ( temperature, inertia )
     END IF

  END SELECT

  WRITE ( unit=output_unit, fmt='(a,a)' ) 'Writing configuration to filename ', filename

  SELECT CASE ( molecule_option )

  CASE ( atoms )

     ! Write out coordinates in same units as box
     box = ( REAL(n) / density ) ** ( 1.0/3.0 )
     WRITE ( unit=output_unit, fmt='(a,t40,f15.5)' ) 'Density',    density
     WRITE ( unit=output_unit, fmt='(a,t40,f15.5)' ) 'Box length', box
     IF ( velocities ) THEN
        CALL write_cnf_atoms ( filename, n, box, box*r, v )
     ELSE
        CALL write_cnf_atoms ( filename, n, box, box*r )
     END IF

  CASE ( chain )

     ! We do not use periodic boundaries for this system
     ! Instead, use "box" variable to store bond length
     WRITE ( unit=output_unit, fmt='(a,t40,f15.5)' ) 'Bond length', bond
     IF ( velocities ) THEN
        CALL write_cnf_atoms ( filename, n, bond, bond*r, v )
     ELSE
        CALL write_cnf_atoms ( filename, n, bond, bond*r )
     END IF

  CASE ( linear, nonlinear )

     ! Write out coordinates in same units as box
     box = ( REAL(n) / density ) ** ( 1.0/3.0 )
     WRITE ( unit=output_unit, fmt='(a,t40,f15.5)' ) 'Density',    density
     WRITE ( unit=output_unit, fmt='(a,t40,f15.5)' ) 'Box length', box
     IF ( velocities ) THEN
        CALL write_cnf_mols ( filename, n, box, box*r, e, v, w )
     ELSE
        CALL write_cnf_mols ( filename, n, box, box*r, e )
     END IF

  END SELECT

  CALL deallocate_arrays

END PROGRAM initialize
