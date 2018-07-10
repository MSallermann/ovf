module ovf
use, intrinsic  :: iso_c_binding
implicit none

integer, parameter  :: OVF_OK      = -1
integer, parameter  :: OVF_ERROR   = -2
integer, parameter  :: OVF_INVALID = -3

integer, parameter  :: OVF_FORMAT_BIN  = -55
integer, parameter  :: OVF_FORMAT_TEXT = -56
integer, parameter  :: OVF_FORMAT_CSV  = -57

type, bind(c) :: c_ovf_file
    type(c_ptr)     :: filename
    integer(c_int)  :: found
    integer(c_int)  :: is_ovf
    integer(c_int)  :: n_segments
    type(c_ptr)     :: file_handle
end type c_ovf_file

type, bind(c) :: c_ovf_segment
    type(c_ptr)         :: title
    type(c_ptr)         :: comment
    integer(kind=c_int) :: valuedim
    type(c_ptr)         :: valueunits
    type(c_ptr)         :: valuelabels

    type(c_ptr)         :: meshtype
    type(c_ptr)         :: meshunits

    integer(kind=c_int) :: pointcount

    integer(kind=c_int) :: n_cells(3)
    integer(kind=c_int) :: N

    real(kind=c_float)  :: bounds_min(3)
    real(kind=c_float)  :: bounds_max(3)

    real(kind=c_float)  :: lattice_constant
    real(kind=c_float)  :: bravais_vectors(3,3)
end type c_ovf_segment

type :: ovf_segment
    character(len=:), allocatable :: Title, Comment, ValueUnits, ValueLabels,  MeshType, MeshUnits
    integer                       :: ValueDim, PointCount, N_Cells(3), N 
    real(8)                       :: bounds_min(3), bounds_max(3), lattice_constant, bravais_vectors(3,3)
contains
    procedure :: initialize       => initialize_segment
end type ovf_segment 

type :: ovf_file
    character(len=:), allocatable   :: filename
    logical                         :: found, is_ovf
    integer                         :: n_segments
    character(len=:), allocatable   :: latest_message
    type(c_ptr)                     :: private_file_binding
contains
    procedure :: open_file           => open_file
    procedure :: read_segment_header => read_segment_header
    procedure :: read_segment_data_4
    procedure :: read_segment_data_8
    GENERIC   :: read_segment_data   => read_segment_data_4, read_segment_data_8
    procedure :: write_segment_4
    procedure :: write_segment_8
    GENERIC   :: write_segment       => write_segment_4, write_segment_8
    procedure :: append_segment_4
    procedure :: append_segment_8
    GENERIC   :: append_segment      => append_segment_4, append_segment_8
    procedure :: close_file          => close_file
end type ovf_file

contains

    ! Helper function to generate a Fortran string from a C char pointer
    function get_string(c_pointer) result(f_string)
        use, intrinsic :: iso_c_binding
        implicit none
        type(c_ptr), intent(in)         :: c_pointer
        character(len=:), allocatable   :: f_string

        character(len=:), pointer       :: f_ptr
        integer(c_size_t)               :: l_str

        interface
            function c_strlen(str_ptr) bind ( C, name = "strlen" ) result(len)
            use, intrinsic :: iso_c_binding
                type(c_ptr), value      :: str_ptr
                integer(kind=c_size_t)  :: len
            end function c_strlen
        end interface

        call c_f_pointer(c_pointer, f_ptr)
        l_str = c_strlen(c_pointer)

        f_string = f_ptr(1:l_str)
    end function get_string


    ! Helper function to create C-struct c_ovf_secment from Fortran type ovf_segment
    function get_c_ovf_segment(segment) result(c_segment)
        use, intrinsic :: iso_c_binding
        implicit none
        type(ovf_segment), intent(in), target   :: segment
        type(c_ovf_segment)                     :: c_segment

        c_segment%title      = c_loc(segment%Title)
        c_segment%comment    = c_loc(segment%Comment)
        c_segment%valueunits = c_loc(segment%ValueUnits)
        c_segment%valuedim   = segment%ValueDim
        c_segment%n_cells(:) = segment%n_cells(:)
        c_segment%N          = product(segment%n_cells)
    end function get_c_ovf_segment


    ! Helper function to turn C-struct c_ovf_secment into Fortran type ovf_segment
    subroutine fill_ovf_segment(c_segment, segment)
        use, intrinsic :: iso_c_binding
        implicit none
        type(c_ovf_segment), intent(in)    :: c_segment
        type(ovf_segment),   intent(inout) :: segment

        segment%Title      = get_string(c_segment%title)
        segment%Comment    = get_string(c_segment%comment)

        segment%ValueLabels = get_string(c_segment%valuelabels)
        segment%ValueUnits = get_string(c_segment%valueunits)
        segment%ValueDim   = c_segment%valuedim

        segment%MeshUnits = get_string(c_segment%meshunits)
        segment%MeshType = get_string(c_segment%meshtype)

        segment%N_Cells(:) = c_segment%n_cells(:)
        segment%N          = product(c_segment%n_cells)
    end subroutine fill_ovf_segment


    ! Helper function to get latest message
    subroutine handle_messages(file)
        implicit none

        type(ovf_file)  :: file
        type(c_ptr)     :: message_ptr

        interface
            function ovf_latest_message(file) &
                            bind ( C, name = "ovf_latest_message" ) &
                            result(message)
            use, intrinsic :: iso_c_binding
                type(c_ptr), value  :: file
                type(c_ptr)         :: message
            end function ovf_latest_message
        end interface

        message_ptr = ovf_latest_message(file%private_file_binding)
        file%latest_message = get_string(message_ptr)

    end subroutine handle_messages


    subroutine open_file(self, filename)
        implicit none
        class(ovf_file)                 :: self
        character(len=*), intent(in)    :: filename

        type(c_ovf_file), pointer       :: c_file
        type(c_ptr)                     :: c_file_ptr

        interface
            function ovf_open(filename) &
                            bind ( C, name = "ovf_open" ) 
            use, intrinsic :: iso_c_binding
                character(len=1,kind=c_char)    :: filename(*)
                type(c_ptr)                     :: ovf_open
            end function ovf_open
        end interface

        c_file_ptr = ovf_open(trim(filename) // c_null_char)
        call c_f_pointer(c_file_ptr, c_file)

        self%filename      = get_string(c_file%filename)
        self%found         = c_file%found  == 1
        self%is_ovf        = c_file%is_ovf == 1
        self%n_segments    = c_file%n_segments
        self%private_file_binding = c_file_ptr
    end subroutine open_file


    subroutine initialize_segment(self)
        implicit none
        class(ovf_segment)              :: self

        type(c_ovf_segment), pointer     :: c_segment
        type(c_ptr)                     :: c_segment_ptr

        interface
            function ovf_segment_initialize() &
                bind ( C, name = "ovf_segment_initialize" ) 
            use, intrinsic :: iso_c_binding
                type(c_ptr) :: ovf_segment_initialize
            end function ovf_segment_initialize
        end interface

        c_segment_ptr = ovf_segment_initialize()
        call c_f_pointer(c_segment_ptr, c_segment)

        call fill_ovf_segment(c_segment, self)

    end subroutine initialize_segment


    function read_segment_header(self, segment) result(success)
        implicit none
        class(ovf_file)             :: self
        type(ovf_segment)           :: segment
        integer                     :: success

        type(c_ovf_segment), target :: c_segment
        type(c_ptr)                 :: c_segment_ptr

        interface
            function ovf_read_segment_header(file, index, segment) &
                                            bind ( C, name = "ovf_read_segment_header" ) &
                                            result(success)
            use, intrinsic :: iso_c_binding
            Import :: c_ovf_file, c_ovf_segment
                type(c_ptr), value              :: file
                integer(kind=c_int), value      :: index 
                type(c_ptr), value              :: segment
                integer(kind=c_int)             :: success
            end function ovf_read_segment_header
        end interface

        c_segment_ptr = c_loc(c_segment)
        success = ovf_read_segment_header(self%private_file_binding, 0, c_segment_ptr)

        if ( success == OVF_OK) then
            call fill_ovf_segment(c_segment, segment)
        end if

        call handle_messages(self)

    end function read_segment_header


    function read_segment_data_4(self, segment, array, index_in) result(success)
        implicit none
        class(ovf_file)                     :: self
        type(ovf_segment), intent(in)       :: segment
        real(kind=4), allocatable, target   :: array(:,:)
        integer, optional, intent(in)       :: index_in
        integer                             :: success

        integer                             :: index
        type(c_ovf_segment), target         :: c_segment
        type(c_ptr)                         :: c_segment_ptr
        type(c_ptr)                         :: c_array_ptr

        interface
            function ovf_read_segment_data_4(file, index, segment, array) &
                                            bind ( C, name = "ovf_read_segment_data_4" ) &
                                            result(success)
            use, intrinsic :: iso_c_binding
            Import :: c_ovf_file, c_ovf_segment
                type(c_ptr), value          :: file
                integer(kind=c_int), value  :: index
                type(c_ptr), value          :: segment
                type(c_ptr), value          :: array
                integer(kind=c_int)         :: success
            end function ovf_read_segment_data_4
        end interface

        if( present(index_in) ) then
            index = index_in
        else
            index = 1
        end if

        if (allocated(array)) then
            ! TODO: check array dimensions
        else
            allocate( array(segment%ValueDim, segment%N) )
            array(:,:) = 0
        endif

        ! Parse into C-structure
        c_segment = get_c_ovf_segment(segment)

        ! Get C-pointers to C-structures
        c_segment_ptr = c_loc(c_segment)
        c_array_ptr   = c_loc(array(1,1))

        ! Call the C-API
        success = ovf_read_segment_data_4(self%private_file_binding, index-1, c_segment_ptr, c_array_ptr)

        call handle_messages(self)

    end function read_segment_data_4


    function read_segment_data_8(self, segment, array, index_in) result(success)
        implicit none
        class(ovf_file)                     :: self
        type(ovf_segment), intent(in)       :: segment
        real(kind=8), allocatable, target   :: array(:,:)
        integer, optional, intent(in)       :: index_in
        integer                             :: success

        integer                     :: index
        type(c_ovf_segment), target :: c_segment
        type(c_ptr)                 :: c_segment_ptr
        type(c_ptr)                 :: c_array_ptr

        interface
            function ovf_read_segment_data_8(file, index, segment, array) &
                                            bind ( C, name = "ovf_read_segment_data_8" ) &
                                            result(success)
            use, intrinsic :: iso_c_binding
            Import :: c_ovf_file, c_ovf_segment
                type(c_ptr), value          :: file
                integer(kind=c_int), value  :: index
                type(c_ptr), value          :: segment
                type(c_ptr), value          :: array
                integer(kind=c_int)         :: success
            end function ovf_read_segment_data_8
        end interface

        if( present(index_in) ) then
            index = index_in
        else
            index = 1
        end if

        if (allocated(array)) then
            ! TODO: check array dimensions
        else
            allocate( array(segment%ValueDim, segment%N) )
            array(:,:) = 0
        endif

        ! Parse into C-structure
        c_segment = get_c_ovf_segment(segment)

        ! Get C-pointers to C-structures
        c_segment_ptr = c_loc(c_segment)
        c_array_ptr   = c_loc(array(1,1))

        ! Call the C-API
        success = ovf_read_segment_data_8(self%private_file_binding, index-1, c_segment_ptr, c_array_ptr)

        call handle_messages(self)

    end function read_segment_data_8


    function write_segment_4(self, segment, array, fileformat_in) result(success)
        implicit none
        class(ovf_file)                     :: self
        type(ovf_segment), intent(in)       :: segment
        real(kind=4), allocatable, target   :: array(:,:)
        integer, optional, intent(in)       :: fileformat_in
        integer                             :: success

        integer                       :: fileformat
        type(c_ovf_segment), target           :: c_segment
        type(c_ptr)                   :: c_segment_ptr
        type(c_ptr)                   :: c_array_ptr

        interface
            function ovf_write_segment_4(file, segment, array, fileformat) &
                                            bind ( C, name = "ovf_write_segment_4" ) &
                                            result(success)
            use, intrinsic :: iso_c_binding
            Import :: c_ovf_file, c_ovf_segment
                type(c_ptr), value          :: file
                type(c_ptr), value          :: segment
                type(c_ptr), value          :: array
                integer(kind=c_int), value  :: fileformat
                integer(kind=c_int)         :: success
            end function ovf_write_segment_4
        end interface

        if( present(fileformat_in) ) then
            fileformat = fileformat_in
        else
            fileformat = OVF_FORMAT_BIN
        end if

        ! Parse into C-structure
        c_segment = get_c_ovf_segment(segment)

        ! Get C-pointers to C-structures
        c_segment_ptr = c_loc(c_segment)
        c_array_ptr   = c_loc(array(1,1))

        ! Call the C-API
        success = ovf_write_segment_4(self%private_file_binding, c_segment_ptr, c_array_ptr, fileformat)

        call handle_messages(self)

    end function write_segment_4


    function write_segment_8(self, segment, array, fileformat_in) result(success)
        implicit none
        class(ovf_file)                     :: self
        type(ovf_segment), intent(in)       :: segment
        real(kind=8), allocatable, target   :: array(:,:)
        integer, optional, intent(in)       :: fileformat_in
        integer                             :: success

        integer                     :: fileformat
        type(c_ovf_segment), target :: c_segment
        type(c_ptr)                 :: c_segment_ptr
        type(c_ptr)                 :: c_array_ptr

        interface
            function ovf_write_segment_8(file, segment, array, fileformat) &
                                            bind ( C, name = "ovf_write_segment_8" ) &
                                            result(success)
            use, intrinsic :: iso_c_binding
            Import :: c_ovf_file, c_ovf_segment
                type(c_ptr), value          :: file
                type(c_ptr), value          :: segment
                type(c_ptr), value          :: array
                integer(kind=c_int), value  :: fileformat
                integer(kind=c_int)         :: success
            end function ovf_write_segment_8
        end interface

        if( present(fileformat_in) ) then
            fileformat = fileformat_in
        else
            fileformat = OVF_FORMAT_BIN
        end if

        ! Parse into C-structure
        c_segment = get_c_ovf_segment(segment)

        ! Get C-pointers to C-structures
        c_segment_ptr = c_loc(c_segment)
        c_array_ptr   = c_loc(array(1,1))

        ! Call the C-API
        success = ovf_write_segment_8(self%private_file_binding, c_segment_ptr, c_array_ptr, fileformat)

        call handle_messages(self)

    end function write_segment_8


    function append_segment_4(self, segment, array, fileformat_in) result(success)
        implicit none
        class(ovf_file)                     :: self
        type(ovf_segment), intent(in)       :: segment
        real(kind=4), allocatable, target   :: array(:,:)
        integer, optional, intent(in)       :: fileformat_in
        integer                             :: success

        integer                     :: fileformat
        type(c_ovf_segment), target :: c_segment
        type(c_ptr)                 :: c_segment_ptr
        type(c_ptr)                 :: c_array_ptr

        interface
            function ovf_append_segment_4(file, segment, array, fileformat) &
                                            bind ( C, name = "ovf_append_segment_4" ) &
                                            result(success)
            use, intrinsic :: iso_c_binding
            Import :: c_ovf_file, c_ovf_segment
                type(c_ptr), value          :: file
                type(c_ptr), value          :: segment
                type(c_ptr), value          :: array
                integer(kind=c_int), value  :: fileformat
                integer(kind=c_int)         :: success
            end function ovf_append_segment_4
        end interface

        if( present(fileformat_in) ) then
            fileformat = fileformat_in
        else
            fileformat = OVF_FORMAT_BIN
        end if

        ! Parse into C-structure
        c_segment = get_c_ovf_segment(segment)

        ! Get C-pointers to C-structures
        c_segment_ptr = c_loc(c_segment)
        c_array_ptr   = c_loc(array(1,1))

        ! Call the C-API
        success = ovf_append_segment_4(self%private_file_binding, c_segment_ptr, c_array_ptr, fileformat)

        call handle_messages(self)

    end function append_segment_4


    function append_segment_8(self, segment, array, fileformat_in) result(success)
        implicit none
        class(ovf_file)                     :: self
        type(ovf_segment), intent(in)       :: segment
        real(kind=8), allocatable, target   :: array(:,:)
        integer, optional, intent(in)       :: fileformat_in
        integer                             :: success

        integer                     :: fileformat
        type(c_ovf_segment), target :: c_segment
        type(c_ptr)                 :: c_segment_ptr
        type(c_ptr)                 :: c_array_ptr

        interface
            function ovf_append_segment_8(file, segment, array, fileformat) &
                                            bind ( C, name = "ovf_append_segment_8" ) &
                                            result(success)
            use, intrinsic :: iso_c_binding
            Import :: c_ovf_file, c_ovf_segment
                type(c_ptr), value          :: file
                type(c_ptr), value          :: segment
                type(c_ptr), value          :: array
                integer(kind=c_int), value  :: fileformat
                integer(kind=c_int)         :: success
            end function ovf_append_segment_8
        end interface

        if( present(fileformat_in) ) then
            fileformat = fileformat_in
        else
            fileformat = OVF_FORMAT_BIN
        end if

        ! Parse into C-structure
        c_segment = get_c_ovf_segment(segment)

        ! Get C-pointers to C-structures
        c_segment_ptr = c_loc(c_segment)
        c_array_ptr   = c_loc(array(1,1))

        ! Call the C-API
        success = ovf_append_segment_8(self%private_file_binding, c_segment_ptr, c_array_ptr, fileformat)

        call handle_messages(self)

    end function append_segment_8


    function close_file(self) result(success)
        implicit none
        class(ovf_file) :: self
        integer         :: success

        interface
            function ovf_close(file) &
                                bind ( C, name = "ovf_close" ) &
                                result(success)
            use, intrinsic :: iso_c_binding
                type(c_ptr), value              :: file
                integer(kind=c_int)             :: success
            end function ovf_close
        end interface

        success = ovf_close(self%private_file_binding)

        call handle_messages(self)

    end function close_file


end module ovf