

C----*|--.---------.---------.---------.---------.---------.---------.-|-------|
      SUBROUTINE SAVE_STATS_CHAN(FINAL)
C----*|--.---------.---------.---------.---------.---------.---------.-|-------|
      INCLUDE 'header'

      CHARACTER*35 FNAME
      CHARACTER*10 GNAME
      LOGICAL FINAL
      integer i,j,k,n
      real*8 uc, ubulk
    
! This variable is used to add up scalar diagnostics
      real*8 thsum(0:NY+1)
 
! These variables are used to store and write 2D slices 
      real*8 varxy(0:NXM,1:NY),varzy(0:NZP-1,1:NY),varxz(0:NXM,0:NZP-1)

      IF (RANK.EQ.0) 
     &     WRITE(6,*) 'Saving flow statistics.'

      IF (USE_MPI) THEN
        call mpi_barrier(MPI_COMM_WORLD,ierror)
        CALL GHOST_CHAN_MPI
      END IF

C Apply Boundary conditions to velocity field
      IF (USE_MPI) THEN
        CALL APPLY_BC_VEL_MPI
      ELSE
        CALL APPLY_BC_VEL_LOWER
        CALL APPLY_BC_VEL_UPPER
      END IF

      if (FINAL) then
! We are done with the simulation

        IF (RANKZ.EQ.0) THEN
        IF (USE_MPI) THEN
          FNAME='stats'//trim(MPI_IO_NUM)//'.txt'
        ELSE
          FNAME='stats.txt'
        END IF

        open(20,file=FNAME,form='formatted',status='unknown')
        do j=1,NY
          write(20,201) j,GYF(j),UBAR(j),VBAR(j),WBAR(j)
        end do
201     format(I3,',',F16.9,',',F16.9,',',F16.9,',',F16.9)
        do n=1,N_TH
        do j=1,NY
          write(20,202) j,GYF(j),THBAR(j,n)
        end do
        end do
202     format(I3,',',F16.9,',',F16.9)
        close(20)
        END IF

      else

! Compute and write out the centerline velocity
      IF (NPROCY.EQ.1) THEN
      if (int(float(NY)/2.) .eq. float(NY)/2.) then
! IF NY is even
        uc=dble(CU1(0,0,int(float(NY)/2.))) 
      else
        uc=0.5*(dble(CU1(0,0,int(float(NY)/2.)-1))
     +         +dble(CU1(0,0,int(float(NY)/2.))))
      end if
      write(*,*) 'Centerline velocity = ', uc 
! Compute and write out bulk velocity
      END IF

! We are in the middle of a run, compile statistics
! First get the number of samples taken so far
      IF (RANK.EQ.0) write(*,*) 'TIME, DELTA_T: ',TIME, DELTA_T
      IF (RANKZ.EQ.0) THEN
         NSAMPLES=NSAMPLES+1
! Get the mean velocity
         do j=1,NY
            UBAR(j)=(1./float(NSAMPLES))*dble(CU1(0,0,j))
     &           +((float(NSAMPLES)-1.)/float(NSAMPLES))*UBAR(j)
            VBAR(j)=(1./float(NSAMPLES))*dble(CU2(0,0,j))
     &           +((float(NSAMPLES)-1.)/float(NSAMPLES))*VBAR(j)
            WBAR(j)=(1./float(NSAMPLES))*dble(CU3(0,0,j))
     &           +((float(NSAMPLES)-1.)/float(NSAMPLES))*WBAR(j)
            do n=1,N_TH
               THBAR(j,n)=(1./float(NSAMPLES))*dble(CTH(0,0,j,n))
     &         +((float(NSAMPLES)-1.)/float(NSAMPLES))*THBAR(j,n)
            end do
         end do

! Integrate the instantaneous mean profile numerically at GY points
         UME=CU1(0,0,:)
      ELSE
         UME=0.d0
      END IF
      CALL INTEGRATE_Y_VAR(UME,UBULK,MPI_COMM_WORLD)
! Write out UBULK
      IF (RANK.EQ.0) write(*,*) 'UBULK: ',UBULK

! Save CUi
      do k=0,TNKZ
        do i=0,NXP-1 ! NKX
          do j=0,NY+1
            CR1(i,k,j)=CU1(i,k,j)
            CR2(i,k,j)=CU2(i,k,j)
            CR3(i,k,j)=CU3(i,k,j)
          end do
        end do
      end do

! Get the mean value of the velocities
      IF (RANKZ.EQ.0) THEN
         ume=dble(CU1(0,0,:))
         vme=dble(CU2(0,0,:))
         wme=dble(CU3(0,0,:)) 
         DO n=1,N_TH
            thme(:,n)=dble(CTH(0,0,:,n))
         END DO
      END IF
      CALL MPI_BCAST(ume,NY+2,MPI_DOUBLE_PRECISION,0,
     &     MPI_COMM_Z,ierror)
      CALL MPI_BCAST(vme,NY+2,MPI_DOUBLE_PRECISION,0,
     &     MPI_COMM_Z,ierror)
      CALL MPI_BCAST(wme,NY+2,MPI_DOUBLE_PRECISION,0,
     &     MPI_COMM_Z,ierror)
      IF (N_TH.GT.0) CALL MPI_BCAST(thme,(NY+2)*N_TH,
     &     MPI_DOUBLE_PRECISION,0,MPI_COMM_Z,ierror)

! Convert to physical space
      call fft_xz_to_physical(CU1,U1,0,NY+1)
      call fft_xz_to_physical(CU2,U2,0,NY+1)
      call fft_xz_to_physical(CU3,U3,0,NY+1)

! Get the turbulent kinetic energy at each level 
      do j=1,NY
        urms(j)=0.
        vrms(j)=0.
        wrms(j)=0.
      do k=0,NZP-1
      do i=0,NXM 
        urms(j)=urms(j)+(U1(i,k,j)-ume(j))**2.
        vrms(j)=vrms(j)+0.5*((U2(i,k,j  )-vme(j  ))**2. +
     &                       (U2(i,k,j+1)-vme(j+1))**2. )
        wrms(j)=wrms(j)+(U3(i,k,j)-wme(j))**2.
      end do
      end do
      end do

      call mpi_allreduce(mpi_in_place,urms,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      call mpi_allreduce(mpi_in_place,vrms,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      call mpi_allreduce(mpi_in_place,wrms,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)

      do j=1,NY
        urms(j)=sqrt(urms(j)/(float(NZ)*float(NX)))
        vrms(j)=sqrt(vrms(j)/(float(NZ)*float(NX)))
        wrms(j)=sqrt(wrms(j)/(float(NZ)*float(NX)))
      end do 

      ! Get the bulk rms value
      CALL INTEGRATE_Y_VAR(urms,urms_b,MPI_COMM_Y)
      CALL INTEGRATE_Y_VAR(vrms,vrms_b,MPI_COMM_Y)
      CALL INTEGRATE_Y_VAR(wrms,wrms_b,MPI_COMM_Y)

! Compute the Reynolds stress and mean velocity gradient
      do j=1,NY
        uv(j)=0. 
        uw(j)=0.
        wv(j)=0.
      do k=0,NZP-1
      do i=0,NXM
        uv(j)=uv(j)+(U1(i,k,j)-ume(j))
     +    *(0.5*(U2(i,k,j)+U2(i,k,j+1))
     &    -0.5*(vme(j)+vme(j+1)))
        wv(j)=wv(j)+(U3(i,k,j)-wme(j))
     +    *(0.5*(U2(i,k,j)+U2(i,k,j+1))
     &    -0.5*(vme(j)+vme(j+1)))
        uw(j)=uw(j)+(U1(i,k,j)-ume(j))
     +    *(U3(i,k,j)-wme(j))
      end do
      end do
      end do

      call mpi_allreduce(mpi_in_place,uv,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      call mpi_allreduce(mpi_in_place,uw,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      call mpi_allreduce(mpi_in_place,wv,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      
      do j=1,NY
        uv(j)=uv(j)/(float(NZ)*float(NX))
        uw(j)=uw(j)/(float(NZ)*float(NX))
        wv(j)=wv(j)/(float(NZ)*float(NX))
      end do
              
! Get the y-derivative of the mean velocity at GY points
      do j=1,NY
        dudy(j)=(ume(j)-ume(j-1))/(GYF(j)-GYF(j-1))
        dwdy(j)=(wme(j)-wme(j-1))/(GYF(j)-GYF(j-1))
      end do

! Calculate the mean square shear
      do j=1,NY
        shear(j)=0.d0
        do k=0,NZP-1
          do i=0,NXM
            shear(j)=shear(j)
     &            +((U1(i,k,j+1)-U1(i,k,j-1))/(2.d0*DYF(j)))**2.d0
     &            +((U3(i,k,j+1)-U3(i,k,j-1))/(2.d0*DYF(j)))**2.d0
          end do
        end do
      end do
      call mpi_allreduce(mpi_in_place,shear,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      do j=1,NY
        shear(j)=shear(j)/dble(NX*NZ)
      end do

! Write out the bulk rms velocity
      if (RANK.eq.0) then
         write(*,*) '<U_rms>: ',urms_b
         write(*,*) '<V_rms>: ',vrms_b
         write(*,*) '<W_rms>: ',wrms_b
      end if

! Get the rms vorticity
! First, get the x-component in fourier space
      do j=1,NY
      do k=0,TNKZ
      do i=0,NXP-1 !NKX
        CS1(i,k,j)=(CR3(i,k,j+1)-CR3(i,k,j-1))/(2.d0*DYF(j))
     &            -CIKZ(K)*0.5d0*(CR2(i,k,j+1)+CR2(i,k,j))
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CS1,S1,0,NY+1)
! Get the rms value
      do j=1,NY
      omega_x(j)=0.d0
      do k=0,NZP-1
      do i=0,NXM
        omega_x(j)=omega_x(j)+S1(i,k,j)**2.d0
      end do
      end do
      end do
      call mpi_allreduce(mpi_in_place,omega_x,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      do j=1,NY
      omega_x(j)=sqrt(omega_x(j)/(dble(NX)*dble(NZ)))
      end do

! Now, get the y-component in fourier space
      do j=1,NY
      do k=0,TNKZ
      do i=0,NXP-1 !NKX
        CS1(i,k,j)=CIKZ(k)*CR1(i,k,j)-CIKX(i)*CR3(i,k,j)
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CS1,S1,0,NY+1)
! Get the rms value
      do j=1,NY
      omega_y(j)=0.d0
      do k=0,NZP-1
      do i=0,NXM
        omega_y(j)=omega_y(j)+S1(i,k,j)**2.d0
      end do
      end do
      end do
      call mpi_allreduce(mpi_in_place,omega_y,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      do j=1,NY
      omega_y(j)=sqrt(omega_y(j)/(dble(NX)*dble(NZ)))
      end do

! Now, get the y-component in fourier space
      do j=1,NY
      do k=0,TNKZ
      do i=0,NXP-1 ! NKX
        CS1(i,k,j)=CIKX(i)*0.5d0*(CR2(i,k,j+1)+CR2(i,k,j))
     &             -(CR1(i,k,j+1)-CR1(i,k,j-1))/(2.d0*DYF(j))
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CS1,S1,0,NY+1)
! Get the rms value
      do j=1,NY
      omega_z(j)=0.d0
      do k=0,NZP-1
      do i=0,NXM
        omega_z(j)=omega_z(j)+S1(i,k,j)**2.d0
      end do
      end do
      end do
      call mpi_allreduce(mpi_in_place,omega_z,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)
      do j=1,NY
      omega_z(j)=sqrt(omega_z(j)/(dble(NX)*dble(NZ)))
      end do

! Write out the mean statistics at each time
      IF (RANKZ.EQ.0) THEN
      IF (USE_MPI) THEN
        FNAME='mean'//trim(MPI_IO_NUM)//'.txt'
      ELSE
        FNAME='mean.txt'
      END IF
      open(40,file=FNAME,form='formatted',status='unknown')
      write(40,*) TIME_STEP,TIME,DELTA_T
      write(40,*) UBULK
      do j=1,NY
        write(40,401) j,GYF(J),ume(j)
     +      ,0.5*(vme(j+1)+vme(j))
     +      ,wme(j),urms(j),vrms(j),wrms(j)
     +      ,uv(j),uw(j),wv(j),dudy(j),dwdy(j),dble(cp(0,0,j)),shear(j)
     &      ,omega_x(j),omega_y(j),omega_z(j)
      end do
      END IF

401   format(I3,' ',17(F30.20,' '))


! Do over the number of passive scalars
      do n=1,N_TH

! Save CTH
      do k=0,TNKZ
        do i=0,NXP-1 ! NKX
          do j=0,NY+1
            CRTH(i,k,j,n)=CTH(i,k,j,n)
          end do
        end do
      end do

! Compute the scalar gradient and store in CRi
      do j=1,NY
        do k=0,TNKZ
          do i=0,NXP-1 ! NKX
! Store gradients of TH(:,:,:,n) (if it is used) in CRi
          CR1(i,k,j)=CIKX(i)*CTH(i,k,j,n)
          CR2(i,k,j)=(CTH(i,k,j+1,n)-CTH(i,k,j-1,n))/(GYF(j+1)-GYF(j-1))
          CR3(i,k,j)=CIKZ(k)*CTH(i,k,j,n)
          end do
        end do
      end do
! Convert gradients to physical space
      CALL FFT_XZ_TO_PHYSICAL(CR1,R1,0,NY+1)
      CALL FFT_XZ_TO_PHYSICAL(CR2,R2,0,NY+1)
      CALL FFT_XZ_TO_PHYSICAL(CR3,R3,0,NY+1)

! Convert to physical space

      call mpi_barrier(MPI_COMM_WORLD,ierror)

      CS1(:,:,:)=CTH(:,:,:,N)
      CALL FFT_XZ_TO_PHYSICAL(CS1,S1,0,NY+1)
      TH(:,:,:,N)=S1(:,:,:)

      do j=1,NY
        thsum(j)=0.
      do k=0,NZP-1
      do i=0,NXM
        thsum(j)=thsum(j)+(abs(TH(i,k,j,n)-thme(j,n)))**2.
      end do
      end do
      end do
      call mpi_allreduce(mpi_in_place,thsum,(NY+2),
     &     MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_Z,ierror)
      do j=1,NY
        thrms(j,n)=sqrt(thsum(j)/(float(NZ)*float(NX)))
      end do
! Compute the Reynolds stress and mean velocity gradient
      do j=1,NY
        thsum(j)=0.
      do k=0,NZP-1
      do i=0,NXM
       thsum(j)=thsum(j)+(TH(i,k,j,n)-thme(j,n))
     +    *(0.5*(U2(i,k,j)+U2(i,k,j+1))
     &      -0.5*(vme(j)+vme(j+1)))
      end do
      end do
      end do
      call mpi_allreduce(mpi_in_place,thsum,(NY+2),
     &     MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_Z,ierror)
      do j=1,NY
      thv(j,n)=thsum(j)/(float(NZ)*float(NX))
      end do

! Get the y-derivative of the mean scalar at GY points
      do j=1,NY
        dthdy(j,n)=(thme(j,n)-thme(j-1,n))/(GYF(j)-GYF(j-1))
      end do

! Compute the potential energy dissipation, grad(TH) \cdot grad(TH)
      do j=1,NY
        thsum(j)=0.d0
        do k=0,NZP-1
          do i=0,NXM
            thsum(j)=thsum(j)
     &          +R1(i,k,j)**2.d0+R2(i,k,j)**2.d0+R3(i,k,j)**2.d0
          end do
        end do
      end do
      call mpi_allreduce(mpi_in_place,thsum,(NY+2),
     &       MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_Z,ierror)
      do j=1,NY
        pe_diss(j,n)=thsum(j)/dble(NX*NZ)
      end do

#ifdef HDF5 
      if (MOVIE) then
         FNAME='movie.h5'
         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKZ.EQ.RANKZMOVIE) THEN
            do I=0,NXM
            do J=1,NY
               varxy(i,j)=TH(i,NzMovie,j,n)
            end do
            end do
            GNAME='th'//CHAR(n+48)//'_xy'
            call writeHDF5_xyplane(FNAME,GNAME,varxy)
         END IF
         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKY.EQ.RANKYMOVIE) THEN
            do I=0,NXM
            do J=0,NZP-1
               varxz(i,j)=TH(i,j,NyMovie,n)
            end do
            end do
            GNAME='th'//CHAR(n+48)//'_xz'
            call writeHDF5_xzplane(FNAME,GNAME,varxz)
         END IF
         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         do I=0,NZP-1
         do J=1,NY
            varzy(i,j)=TH(NxMovie,i,j,n)
         end do
         end do
         GNAME='th'//CHAR(n+48)//'_zy'
         call writeHDF5_zyplane(FNAME,GNAME,varzy)

      END IF
#endif

! Convert back to Fourier space
      S1(:,:,:)=TH(:,:,:,N)
      CALL FFT_XZ_TO_FOURIER(S1,CS1,0,NY+1)
      CTH(:,:,:,N)=CS1(:,:,:)

! End do over number of passive scalars, n
      end do

! Write out the mean statistics at each time
      IF (RANKZ.EQ.0) THEN
      IF (USE_MPI) THEN
        FNAME='mean_th'//trim(MPI_IO_NUM)//'.txt'
      ELSE
        FNAME='mean_th.txt'
      END IF
      open(41,file=FNAME,form='formatted',status='unknown')
      write(41,*) TIME_STEP,TIME,DELTA_T
      write(41,*) UBULK
      do n=1,N_TH 
      do j=1,NY
        write(41,402) j,GYF(J),thme(j,n)
     +      ,dthdy(j,n),thrms(j,n),thv(j,n),pe_diss(j,n)
      end do
      end do
      END IF

402   format(I3,' ',6(F30.20,' '))

      IF (RANK.EQ.0) 
     &     write(*,*) 'VERBOSITY: ',VERBOSITY
      if (VERBOSITY.gt.4) then 
      IF (RANK.EQ.0) 
     &        write(*,*) 'Outputting info for gnuplot...'
      open (unit=10, file="solution")
      do i=2,NXM
        do j=2,NYM
          write (10,*) i, j, U1(i,0,j)
        end do
        write (10,*) ""
      end do
      close (10)
      call system ('gnuplot <gnuplot.in') 
      end if

#ifdef HDF5
      if (MOVIE) then
         FNAME='movie.h5'
         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKZ.EQ.RANKZMOVIE) THEN
            do I=0,NXM
            do J=1,NY
               varxy(i,j)=U1(i,NzMovie,j)
            end do
            end do
            GNAME='u_xy'
            call writeHDF5_xyplane(FNAME,GNAME,varxy)
         END IF

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKZ.EQ.RANKZMOVIE) THEN
            do I=0,NXM
            do J=1,NY
               varxy(i,j)=0.5*(U2(i,NzMovie,j)+U2(i,NzMovie,j+1))
            end do
            end do
            GNAME='v_xy'
            call writeHDF5_xyplane(FNAME,GNAME,varxy)
          END IF

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKZ.EQ.RANKZMOVIE) THEN
            do I=0,NXM
            do J=1,NY
               varxy(i,j)=U3(i,NzMovie,j)
            end do
            end do
            GNAME='w_xy'
            call writeHDF5_xyplane(FNAME,GNAME,varxy)
         END IF

         if (LES) then
         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKZ.EQ.RANKZMOVIE) THEN
            do I=0,NXM
            do J=1,NY
               varxy(i,j)=NU_T(i,NzMovie,j)
            end do
            end do
            GNAME='nu_t_xy'
            call writeHDF5_xyplane(FNAME,GNAME,varxy)
         END IF
         end if

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKY.EQ.RANKYMOVIE) THEN
            do I=0,NXM
            do J=0,NZP-1
               varxz(i,j)=U1(i,j,NyMovie)
            end do
            end do
            GNAME='u_xz'
            call writeHDF5_xzplane(FNAME,GNAME,varxz)
         END IF

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKY.EQ.RANKYMOVIE) THEN
            do I=0,NXM
            do J=0,NZP-1
               varxz(i,j)=0.5*(U2(i,j,NyMovie)+U2(i,j,NyMovie+1))
            end do
            end do
            GNAME='v_xz'
            call writeHDF5_xzplane(FNAME,GNAME,varxz)
         END IF 

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKY.EQ.RANKYMOVIE) THEN
            do I=0,NXM
            do J=0,NZP-1
               varxz(i,j)=U3(i,j,NyMovie)
            end do
            end do
            GNAME='w_xz'
            call writeHDF5_xzplane(FNAME,GNAME,varxz)
          END IF

         IF (LES) then
         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (RANKY.EQ.RANKYMOVIE) THEN
            do I=0,NXM
            do J=0,NZP-1
              varxz(i,j)=NU_T(i,j,NyMovie)
            end do
            end do
            GNAME='nu_t_xz'
            call writeHDF5_xzplane(FNAME,GNAME,varxz) 
         end if
         END IF
         
         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         do I=0,NZP-1
         do J=1,NY
            varzy(i,j)=U1(NxMovie,i,j)
         end do
         end do
         GNAME='u_zy'
         call writeHDF5_zyplane(FNAME,GNAME,varzy)

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         do I=0,NZP-1
         do J=1,NY
            varzy(i,j)=0.5*(U2(NxMovie,i,j)+U2(NxMovie,i,j+1))
         end do
         end do
         GNAME='v_zy'
         call writeHDF5_zyplane(FNAME,GNAME,varzy)

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         do I=0,NZP-1
         do J=1,NY
            varzy(i,j)=U3(NxMovie,i,j)
         end do
         end do
         GNAME='w_zy'
         call writeHDF5_zyplane(FNAME,GNAME,varzy)

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
         IF (LES) then
         do I=0,NZP-1
         do J=1,NY
            varzy(i,j)=NU_T(NxMovie,i,j)
         end do
         end do
         GNAME='nu_t_zy'
         call writeHDF5_zyplane(FNAME,GNAME,varzy)
         END IF ! END IF LES

         if (USE_MPI) then
         call mpi_barrier(MPI_COMM_WORLD,ierror)
         end if
        END IF ! END IF MOVIE

#endif

C Convert velocity back to Fourier space
      call fft_xz_to_fourier(U1,CU1,0,NY+1)
      call fft_xz_to_fourier(U2,CU2,0,NY+1)
      call fft_xz_to_fourier(U3,CU3,0,NY+1)

      end if

      IF (RANK.EQ.0) 
     &     write(*,*) 'done save_stats chan' 

      if (USE_MPI) then
      call mpi_barrier(MPI_COMM_WORLD,ierror)
      end if

      RETURN
      END

      subroutine tkebudget_chan
! NOte, it is important to only run this routine after complete R-K
!  time advancement since F1 is overwritten which is needed between R-K steps
      include 'header'

      character*35 FNAME
      integer i,j,k

! Compute the turbulent dissipation rate, epsilon=nu*<du_i/dx_j du_i/dx_j>
      do j=2,NYM
        epsilon(j)=0.
      end do
! Store du/dx in CS1
      do j=2,NYM
      do k=0,TNKZ
      do i=0,NXP-1
        CS1(i,k,j)=CIKX(i)*CR1(i,k,j)
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CS1,S1,0,NY+1)
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+(S1(i,k,j)**2.0)
      end do
      end do
      end do
! Store dv/dx in CS1
      do j=2,NYM
      do k=0,TNKZ
      do i=0,NXP-1
        CS1(i,k,j)=CIKX(i)*(CR2(i,k,j)+CR2(i,k,j+1))/2.0
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CS1,S1,0,NY+1)
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+0.5*(S1(i,k,j)**2.0)
      end do
      end do
      end do
! Compute du/dy at GYF gridpoints, note remove mean
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        F1(i,k,j)=((U1(i,k,j+1)-CR1(0,0,j+1))
     &      -(U1(i,k,j-1)-CR1(0,0,j-1)))/(GY(j)+GY(j+1))
      end do
      end do
      end do
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+0.5*(F1(i,k,j)**2.0)
! Cross term dvdx*dudy
        epsilon(j)=epsilon(j)+(S1(i,k,j)*F1(i,k,j))
      end do
      end do
      end do
! Store dw/dx in CS1
      do j=2,NYM
      do k=0,TNKZ
      do i=0,NXP-1
        CS1(i,k,j)=CIKX(i)*CR3(i,k,j)
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CS1,S1,0,NY+1)
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+0.5*(S1(i,k,j)**2.0)
      end do
      end do
      end do
! Compute du/dz at GYF gridpoints, note remove mean
! Store du/dz in CS1
      do j=2,NYM
      do k=0,TNKZ
      do i=0,NXP-1
        CF1(i,k,j)=CIKZ(k)*CR1(i,k,j)
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CF1,F1,0,NY+1)
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+0.5*(F1(i,k,j)**2.0)
! Cross term dudz*dwdx
        epsilon(j)=epsilon(j)+S1(i,k,j)*F1(i,k,j)
      end do
      end do
      end do
! Compute dv/dy at GYF gridpoints, note remove mean
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        S1(i,k,j)=((U2(i,k,j+1)-CR2(0,0,j+1))-(U2(i,k,j)-CR2(0,0,j)))
     &            /GYF(j)
      end do
      end do
      end do
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+(S1(i,k,j)**2.0)
      end do
      end do
      end do
! Compute dw/dy at GYF gridpoints, note remove mean
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        S1(i,k,j)=((U3(i,k,j+1)-CR3(0,0,j+1))
     &      -(U3(i,k,j-1)-CR3(0,0,j-1)))/(GY(j)+GY(j+1))
      end do
      end do
      end do
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+0.5*(S1(i,k,j)**2.0)
      end do
      end do
      end do
! Store dv/dz in CF1
      do j=2,NYM
      do k=0,TNKZ
      do i=0,NXP-1
        CF1(i,k,j)=CIKZ(k)*(CR2(i,k,j)+CR2(i,k,j+1))/2.0
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CF1,F1,0,NY+1)
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+0.5*(F1(i,k,j)**2.0)
! Cross term dvdz*dwdy
        epsilon(j)=epsilon(j)+S1(i,k,j)*F1(i,k,j)
      end do
      end do
      end do
! Store dw/dz in CS1
      do j=2,NYM
      do k=0,TNKZ
      do i=0,NXP-1
        CS1(i,k,j)=CIKZ(k)*CR3(i,k,j)
      end do
      end do
      end do
! Convert to physical space
      call fft_xz_to_physical(CS1,S1,0,NY+1)
      do j=2,NYM
      do k=0,NZP-1
      do i=0,NXM
        epsilon(j)=epsilon(j)+(S1(i,k,j)**2.0)
      end do
      end do
      end do
      do j=2,NYM
        epsilon(j)=epsilon(j)/float(NX*NZ)
      end do
      call mpi_allreduce(mpi_in_place,epsilon,NY+2,MPI_DOUBLE_PRECISION,
     &     MPI_SUM,MPI_COMM_Z,ierror)

      IF (RANKZ.EQ.0) THEN
! Write out the mean statistics at each time
      IF (USE_MPI) THEN
        FNAME='tke'//trim(MPI_IO_NUM)//'.txt'
      ELSE
        FNAME='tke.txt'
      END IF
      open(45,file=FNAME,form='formatted',status='unknown')
      write(45,*) TIME_STEP,TIME,DELTA_T
      do j=2,NYM
        write(45,401) j,GYF(J),epsilon(j)
      end do
401   format(I3,' ',2(F20.9,' '))
      end if

      return 
      end



