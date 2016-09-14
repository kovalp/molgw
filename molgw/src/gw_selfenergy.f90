!=========================================================================
! This file is part of MOLGW.
! Author: Fabien Bruneval
!
! This file contains the calculation of the GW self-energy
! within different flavors: G0W0, GnW0, GnWn, COHSEX, QSGW
!
!=========================================================================
subroutine gw_selfenergy(selfenergy_approx,nstate,basis,occupation,energy,c_matrix,wpol,se,energy_gw)
 use m_definitions
 use m_mpi
 use m_timing 
 use m_inputparam
 use m_warning,only: issue_warning,msg
 use m_basis_set
 use m_spectral_function
 use m_eri_ao_mo
 use m_tools,only: coeffs_gausslegint
 use m_selfenergy_tools
 implicit none

 integer,intent(in)                 :: nstate,selfenergy_approx
 type(basis_set)                    :: basis
 real(dp),intent(in)                :: occupation(nstate,nspin),energy(nstate,nspin)
 real(dp),intent(in)                :: c_matrix(basis%nbf,nstate,nspin)
 type(spectral_function),intent(in) :: wpol
 type(selfenergy_grid),intent(inout) :: se
 real(dp),intent(out)               :: energy_gw
!=====
 integer               :: iomega
 integer               :: iastate
 integer               :: astate,bstate
 integer               :: istate,ispin,ipole
 real(dp),allocatable  :: bra(:,:)
 real(dp),allocatable  :: bra_exx(:,:)
 real(dp)              :: fact_full_i,fact_empty_i
 real(dp)              :: fact_full_a,fact_empty_a
 real(dp)              :: energy_lw(nstate,nspin)
 character(len=3)      :: ctmp
 integer               :: selfenergyfile
! GW tilde
 real(dp),allocatable  :: vsqchi0vsqm1(:,:)
 real(dp)              :: omega_m_ei,bra2
! LW devel
 complex(dp),allocatable :: omegac(:)
 complex(dp),allocatable :: selfenergy_omegac(:,:,:,:)
 complex(dp),allocatable :: matrix(:,:),eigvec(:,:)
 real(dp),allocatable    :: eigval(:),x1(:),weights(:)
 real(dp)                :: tr_log_gsigma,tr_gsigma,rdiag,mu
 real(dp),allocatable    :: c_matrix_exx(:,:,:)
!=====

 call start_clock(timing_self)

 write(stdout,*)
 select case(selfenergy_approx)
 case(LW,LW2)
   write(stdout,*) 'Perform the calculation of Tr[ ln ( 1 - GSigma ) ]'
 case(GSIGMA)
   write(stdout,*) 'Perform the calculation of Tr[ SigmaG ]'
 case(GV)
   write(stdout,*) 'Perform a perturbative HF calculation'
 case(GWTILDE)
   write(stdout,*) 'Perform a one-shot GWtilde calculation'
   call assert_experimental()
 case(GW)
   write(stdout,*) 'Perform a one-shot G0W0 calculation'
 case(G0W0_IOMEGA)
   write(stdout,*) 'Perform a one-shot G0W0 calculation EXPERIMENTAL!'
   call assert_experimental()
 case(COHSEX)
   write(stdout,*) 'Perform a COHSEX calculation'
   if( ABS(alpha_cohsex - 1.0_dp) > 1.0e-4_dp .OR. ABS(beta_cohsex - 1.0_dp) > 1.0e-4_dp ) then
     write(stdout,'(a,2(2x,f12.6))') ' Tuned COHSEX with parameters alpha, beta: ',alpha_cohsex,beta_cohsex
   endif
 case(GnW0)
   write(stdout,*) 'Perform an eigenvalue self-consistent GnW0 calculation'
 case(GnWn)
   write(stdout,*) 'Perform an eigenvalue self-consistent GnWn calculation'
 case default
   write(stdout,*) 'type:',selfenergy_approx
   call die('gw_selfenergy: calculation type unknown')
 end select



 if(has_auxil_basis) then
   call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix,nsemin,nsemax,ncore_G+1,nvirtual_G-1)
   if( calc_type%selfenergy_approx == LW .OR. calc_type%selfenergy_approx == LW2 .OR. calc_type%selfenergy_approx == GSIGMA ) &
       call calculate_eri_3center_eigen_mixed(basis%nbf,nstate,c_matrix)
 endif

 call clean_allocate('Temporary array',bra,1,wpol%npole_reso,nsemin,nsemax)

 if(selfenergy_approx==LW .OR. selfenergy_approx==LW2 .OR. selfenergy_approx==GSIGMA) then
   call clean_allocate('Temporary array for LW',bra_exx,1,wpol%npole_reso,nsemin,nsemax)
 endif


 energy_gw = 0.0_dp


 !
 ! The ones with imaginary frequencies
 select case(selfenergy_approx)
 case(LW,LW2,G0W0_IOMEGA)
   allocate(omegac(1:se%nomega))
   
   allocate(x1(se%nomega),weights(se%nomega))  
   call coeffs_gausslegint(0.0_dp,1.0_dp,x1,weights,se%nomega)

   mu =-0.10_dp
   write(stdout,*) 'mu is set manually here to',mu
   do iomega=1,se%nomega
     omegac(iomega) = x1(iomega) / ( 1.0_dp - x1(iomega) ) * im + mu
     weights(iomega) = weights(iomega) / (1.0_dp - x1(iomega))**2
     write(stdout,'(i4,3(2x,f12.4))') iomega,REAL(omegac(iomega)),AIMAG(omegac(iomega)),weights(iomega)
   enddo
   deallocate(x1)
 end select


 if( selfenergy_approx == LW .OR. selfenergy_approx == LW2 .OR. selfenergy_approx == GSIGMA ) then
   call issue_warning('reading G\tilde')
   open(1001,form='unformatted')
   read(1001) energy_lw(:,:)
   close(1001,status='delete')
 endif


 !
 ! Which calculation type needs a complex sigma?
 !
 select case(selfenergy_approx)
 case(LW,LW2,G0W0_IOMEGA)                     ! matrix complex
   allocate(selfenergy_omegac(1:se%nomega,nsemin:nsemax,nsemin:nsemax,nspin))
   selfenergy_omegac(:,:,:,:) = 0.0_dp
 end select


 se%sigma(:,:,:)  = 0.0_dp

 do ispin=1,nspin
   do istate=ncore_G+1,nvirtual_G-1 !INNER LOOP of G

     if( MODULO( istate - (ncore_G+1) , nproc_ortho) /= rank_ortho ) cycle

     !
     ! Prepare the bra and ket with the knowledge of index istate and astate
     if( .NOT. has_auxil_basis) then
       ! Here just grab the precalculated value
       do astate=nsemin,nsemax
         iastate = index_prodstate(istate,astate) + (ispin-1) * index_prodstate(nvirtual_W-1,nvirtual_W-1)
         bra(:,astate) = wpol%residu_left(iastate,:)
       end do
     else
       ! Here transform (sqrt(v) * chi * sqrt(v)) into  (v * chi * v)
       bra(:,nsemin:nsemax)     = MATMUL( TRANSPOSE(wpol%residu_left(:,:)) , eri_3center_eigen(:,nsemin:nsemax,istate,ispin) )
       call xsum_auxil(bra)
       if( selfenergy_approx==LW .OR. selfenergy_approx==LW2 .OR. selfenergy_approx==GSIGMA) then
         bra_exx(:,nsemin:nsemax) = MATMUL( TRANSPOSE(wpol%residu_left(:,:)) , eri_3center_eigen_mixed(:,istate,nsemin:nsemax,ispin) )
         call xsum_auxil(bra_exx)
       endif
     endif


     ! The application of residu theorem only retains the pole in certain
     ! quadrants.
     ! The positive poles of W go with the poles of occupied states in G
     ! The negative poles of W go with the poles of empty states in G
     fact_full_i   = occupation(istate,ispin) / spin_fact
     fact_empty_i = (spin_fact - occupation(istate,ispin)) / spin_fact


     do ipole=1,wpol%npole_reso


       select case(selfenergy_approx)

       case(LW,LW2)

         if(ipole==1) write(stdout,*) 'FBFB LW',istate

         do bstate=nsemin,nsemax
           do astate=nsemin,nsemax

             do iomega=1,se%nomega
               selfenergy_omegac(iomega,astate,bstate,ispin) = selfenergy_omegac(iomega,astate,bstate,ispin) &
                        + bra_exx(ipole,astate) * bra_exx(ipole,bstate) &
                          * (  fact_full_i  / ( omegac(iomega) - energy(istate,ispin) + wpol%pole(ipole)  )    &
                             + fact_empty_i / ( omegac(iomega) - energy(istate,ispin) - wpol%pole(ipole) ) )   &
                          / ( omegac(iomega) - energy_lw(astate,ispin) )
             enddo

           enddo
         enddo

       case(GSIGMA)

         do astate=nsemin,nsemax
           fact_full_a   = occupation(astate,ispin) / spin_fact
           fact_empty_a  = (spin_fact - occupation(astate,ispin)) / spin_fact
           !
           ! calculate only the diagonal !
           se%sigma(0,astate,ispin) = se%sigma(0,astate,ispin) &
                    - bra(ipole,astate) * bra(ipole,astate) &
                      * ( REAL(  fact_full_i  * fact_empty_a / ( energy(astate,ispin)  - energy(istate,ispin) + wpol%pole(ipole) - ieta )  , dp )  &
                        - REAL(  fact_empty_i * fact_full_a  / ( energy(astate,ispin)  - energy(istate,ispin) - wpol%pole(ipole) + ieta )  , dp ) )
           se%sigma(1,astate,ispin) = se%sigma(1,astate,ispin) &
                    - bra_exx(ipole,astate) * bra_exx(ipole,astate) &
                      * ( REAL(  fact_full_i  * fact_empty_a / ( energy_lw(astate,ispin)  - energy(istate,ispin) + wpol%pole(ipole) - ieta )  , dp )  &
                        - REAL(  fact_empty_i * fact_full_a  / ( energy_lw(astate,ispin)  - energy(istate,ispin) - wpol%pole(ipole) + ieta )  , dp ) )
         enddo


       case(GW,GnW0,GnWn)

         do astate=nsemin,nsemax
           !
           ! calculate only the diagonal !
           do iomega=-se%nomega,se%nomega
             se%sigma(iomega,astate,ispin) = se%sigma(iomega,astate,ispin) &
                      + bra(ipole,astate) * bra(ipole,astate)                                          & 
                        * ( REAL(  fact_full_i  / ( energy(astate,ispin) + se%omega(iomega) - energy(istate,ispin) + wpol%pole(ipole) - ieta )  , dp )  &
                          + REAL(  fact_empty_i / ( energy(astate,ispin) + se%omega(iomega) - energy(istate,ispin) - wpol%pole(ipole) + ieta )  , dp ) )
           enddo
         enddo

       case(GWTILDE)

         allocate(vsqchi0vsqm1(nauxil_2center,nauxil_2center))

         do astate=nsemin,nsemax
           do iomega=-se%nomega,se%nomega
             omega_m_ei = energy(astate,ispin) + se%omega(iomega) - energy(istate,ispin)
             call dynamical_polarizability(nstate,occupation,energy,omega_m_ei,wpol,vsqchi0vsqm1)

             bra2 = DOT_PRODUCT( eri_3center_eigen(:,astate,istate,ispin) , MATMUL( vsqchi0vsqm1(:,:) , wpol%residu_left(:,ipole)) )

             se%sigma(iomega,astate,ispin) = se%sigma(iomega,astate,ispin) &
                      + bra2 * bra(ipole,astate)                                          & 
                        * ( REAL(  fact_full_i  / ( omega_m_ei + wpol%pole(ipole) - ieta )  , dp )  &
                          + REAL(  fact_empty_i / ( omega_m_ei - wpol%pole(ipole) + ieta )  , dp ) )
           enddo
         enddo

         deallocate(vsqchi0vsqm1)

       case(G0W0_IOMEGA)

         do astate=nsemin,nsemax
           !
           ! calculate only the diagonal !
             do iomega=1,se%nomega
               selfenergy_omegac(iomega,astate,1,ispin) = selfenergy_omegac(iomega,astate,1,ispin) &
                      + bra(ipole,astate) * bra(ipole,astate)                                          & 
                        * ( fact_full_i  / ( omegac(iomega) - energy(istate,ispin) + wpol%pole(ipole) ) &  !  - ieta )    &
                          + fact_empty_i / ( omegac(iomega) - energy(istate,ispin) - wpol%pole(ipole) ) )  ! + ieta )  )
           enddo
         enddo


       case(COHSEX)

         do astate=nsemin,nsemax
           !
           ! SEX
           !
           se%sigma(0,astate,ispin) = se%sigma(0,astate,ispin) &
                      + bra(ipole,astate) * bra(ipole,astate) &
                            * fact_full_i / wpol%pole(ipole) * 2.0_dp  &
                            * beta_cohsex

           !
           ! COH
           !
           se%sigma(0,astate,ispin) = se%sigma(0,astate,ispin) &
                      - bra(ipole,astate) * bra(ipole,astate) &
                            / wpol%pole(ipole)                &
                            * alpha_cohsex

         enddo

       case(GV)
         !
         ! Do nothing: no correlation in this case
         !
       case default 
         call die('BUG')
       end select

     enddo !ipole

   enddo !istate
 enddo !ispin

 ! Sum up the contribution from different poles (= different procs)
 call xsum_ortho(se%sigma)

 if( ALLOCATED(selfenergy_omegac) ) then
   call xsum_ortho(selfenergy_omegac)
 endif


 write(stdout,'(a)') ' Sigma_c(omega) is calculated'


 !
 ! Only the EXPERIMENTAL features need to do some post-processing here!
 select case(selfenergy_approx)
 case(G0W0_IOMEGA) !==========================================================

   if( is_iomaster ) then

     do astate=nsemin,nsemax
       write(ctmp,'(i3.3)') astate
       write(stdout,'(1x,a,a)') 'Printing file: ','selfenergy_omegac_state'//TRIM(ctmp)
       open(newunit=selfenergyfile,file='selfenergy_omegac_state'//TRIM(ctmp))
       write(selfenergyfile,'(a)') '# Re omega (eV)  Im omega (eV)  SigmaC (eV) '
       do iomega=1,se%nomega
         write(selfenergyfile,'(20(f12.6,2x))') omegac(iomega)*Ha_eV,                                     &
                                            selfenergy_omegac(iomega,astate,1,:)*Ha_eV
       enddo
       write(selfenergyfile,*)
       close(selfenergyfile)
     enddo

   endif

 case(GSIGMA) !==========================================================

   energy_gw = 0.5_dp * SUM(se%sigma(1,:,:)) * spin_fact
   write(stdout,*) 'Tr[Sigma tilde G]:',2.0_dp*energy_gw

   energy_gw = 0.5_dp * SUM(se%sigma(0,:,:)) * spin_fact
   write(stdout,*) '       Tr[SigmaG]:',2.0_dp*energy_gw

 case(LW)

   allocate(matrix(nsemin:nsemax,nsemin:nsemax))
   allocate(eigvec(nsemin:nsemax,nsemin:nsemax))
   allocate(eigval(nsemax-nsemin+1))

   tr_log_gsigma = 0.0_dp
   tr_gsigma     = 0.0_dp

   do ispin=1,nspin
     do iomega=1,se%nomega

       rdiag = 0.d0
       do istate=nsemin,nsemax
         rdiag = rdiag + REAL(selfenergy_omegac(iomega,istate,istate,ispin),dp) * 2.0_dp
       enddo

       matrix(:,:) = selfenergy_omegac(iomega,:,:,ispin) + CONJG(TRANSPOSE( selfenergy_omegac(iomega,:,:,ispin) )) &
                    - MATMUL( selfenergy_omegac(iomega,:,:,ispin) , CONJG(TRANSPOSE( selfenergy_omegac(iomega,:,:,ispin) )) )

       call diagonalize(nsemax-nsemin+1,matrix,eigval,eigvec)

       tr_gsigma     = tr_gsigma     + rdiag                         * spin_fact / (2.0 * pi) * weights(iomega)
       tr_log_gsigma = tr_log_gsigma + SUM(LOG( 1.0_dp - eigval(:))) * spin_fact / (2.0 * pi) * weights(iomega)

     enddo
   enddo


   write(stdout,*) 'Tr[Log(1-GSigma)] ',tr_log_gsigma 
   write(stdout,*) 'Tr[GSigma]        ',tr_gsigma 
   write(stdout,*) 'Sum               ',(tr_log_gsigma+tr_gsigma) 
   deallocate(matrix,eigvec,eigval)

 case(LW2)

   allocate(matrix(basis%nbf,basis%nbf))
   allocate(eigvec(basis%nbf,basis%nbf))
   allocate(eigval(basis%nbf))

   tr_log_gsigma = 0.0_dp
   tr_gsigma     = 0.0_dp

   do iomega=1,se%nomega

     matrix(:,:) = MATMUL( selfenergy_omegac(iomega,:,:,1) , selfenergy_omegac(iomega,:,:,1) )   &
                + MATMUL( TRANSPOSE(CONJG(selfenergy_omegac(iomega,:,:,1))) , TRANSPOSE(CONJG(selfenergy_omegac(iomega,:,:,1))) )

     rdiag=0.d0
     do istate=1,basis%nbf
       rdiag = rdiag - REAL(matrix(istate,istate),dp) * spin_fact / (2.0 * pi)   * 0.5_dp  ! -1/2 comes from the log expansion
     enddo


     tr_gsigma = tr_gsigma + rdiag * weights(iomega)

   enddo


   write(stdout,*) 'Tr[tGSigma*tGSigma]        ',tr_gsigma 
   deallocate(matrix,eigvec,eigval)

 end select



 call clean_deallocate('Temporary array',bra)
 if(ALLOCATED(bra_exx)) call clean_deallocate('Temporary array for LW',bra_exx)

 if(has_auxil_basis) then
   call destroy_eri_3center_eigen()
   if( calc_type%selfenergy_approx == LW .OR. calc_type%selfenergy_approx == LW2 .OR. calc_type%selfenergy_approx == GSIGMA ) &
       call calculate_eri_3center_eigen_mixed(basis%nbf,nstate,c_matrix)
 endif

 if(ALLOCATED(omegac)) deallocate(omegac)
 if(ALLOCATED(weights)) deallocate(weights)
 if(ALLOCATED(selfenergy_omegac)) deallocate(selfenergy_omegac)


 call stop_clock(timing_self)


end subroutine gw_selfenergy


!=========================================================================
subroutine gw_selfenergy_qs(nstate,basis,occupation,energy,c_matrix,s_matrix,wpol,selfenergy)
 use m_definitions
 use m_mpi
 use m_timing 
 use m_inputparam
 use m_warning,only: issue_warning,msg
 use m_basis_set
 use m_spectral_function
 use m_eri_ao_mo
 use m_tools,only: coeffs_gausslegint
 use m_selfenergy_tools
 implicit none

 integer,intent(in)                 :: nstate
 type(basis_set)                    :: basis
 real(dp),intent(in)                :: occupation(nstate,nspin),energy(nstate,nspin)
 real(dp),intent(in)                :: c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(in)                :: s_matrix(basis%nbf,basis%nbf)
 type(spectral_function),intent(in) :: wpol
 real(dp),intent(out)               :: selfenergy(basis%nbf,basis%nbf,nspin)
!=====
 integer               :: ipstate,pstate,qstate,istate
 integer               :: ispin,ipole
 real(dp),allocatable  :: bra(:,:)
 real(dp)              :: fact_full_i,fact_empty_i
!=====

 call start_clock(timing_self)

 write(stdout,*)
 select case(calc_type%selfenergy_approx)
 case(GW)
   write(stdout,*) 'Perform a QP self-consistent GW calculation (QSGW)'
 case(COHSEX)
   write(stdout,*) 'Perform a self-consistent COHSEX calculation'
   if( ABS(alpha_cohsex - 1.0_dp) > 1.0e-4_dp .OR. ABS(beta_cohsex - 1.0_dp) > 1.0e-4_dp ) then
     write(stdout,'(a,2(2x,f12.6))') ' Tuned COHSEX with parameters alpha, beta: ',alpha_cohsex,beta_cohsex
   endif
 case default
   call die('gw_selfenergy_qs: calculation type unknown')
 end select


 if(has_auxil_basis) then
   call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix,nsemin,nsemax,ncore_G+1,nvirtual_G-1)
 endif

 call clean_allocate('Temporary array',bra,1,wpol%npole_reso,nsemin,nsemax)


 selfenergy(:,:,:)  = 0.0_dp
 do ispin=1,nspin
   do istate=ncore_G+1,nvirtual_G-1 !INNER LOOP of G

     if( MODULO( istate - (ncore_G+1) , nproc_ortho) /= rank_ortho ) cycle

     !
     ! Prepare the bra and ket with the knowledge of index istate and pstate
     if( .NOT. has_auxil_basis) then
       ! Here just grab the precalculated value
       do pstate=nsemin,nsemax
         ipstate = index_prodstate(istate,pstate) + (ispin-1) * index_prodstate(nvirtual_W-1,nvirtual_W-1)
         bra(:,pstate) = wpol%residu_left(ipstate,:)
       end do
     else
       ! Here transform (sqrt(v) * chi * sqrt(v)) into  (v * chi * v)
       bra(:,nsemin:nsemax)     = MATMUL( TRANSPOSE(wpol%residu_left(:,:)) , eri_3center_eigen(:,nsemin:nsemax,istate,ispin) )
       call xsum_auxil(bra)
     endif


     ! The application of residu theorem only retains the pole in certain
     ! quadrants.
     ! The positive poles of W go with the poles of occupied states in G
     ! The negative poles of W go with the poles of empty states in G
     fact_full_i   = occupation(istate,ispin) / spin_fact
     fact_empty_i = (spin_fact - occupation(istate,ispin)) / spin_fact


     do ipole=1,wpol%npole_reso


       select case(calc_type%selfenergy_approx)

       case(GW)

         do qstate=nsemin,nsemax
           do pstate=nsemin,nsemax

             selfenergy(pstate,qstate,ispin) = selfenergy(pstate,qstate,ispin) &
                        + bra(ipole,pstate) * bra(ipole,qstate)                            &  
                          * ( REAL(  fact_full_i  / ( energy(qstate,ispin) - ieta  - energy(istate,ispin) + wpol%pole(ipole) ) , dp ) &
                            + REAL(  fact_empty_i / ( energy(qstate,ispin) + ieta  - energy(istate,ispin) - wpol%pole(ipole) ) , dp ) )

           enddo
         enddo

       case(COHSEX) 
         do qstate=nsemin,nsemax
           do pstate=nsemin,nsemax
             !
             ! SEX
             !
             selfenergy(pstate,qstate,ispin) = selfenergy(pstate,qstate,ispin) &
                        + bra(ipole,pstate) * bra(ipole,qstate)                                & 
                              * fact_full_i / wpol%pole(ipole) * 2.0_dp                        &
                              * beta_cohsex

             !
             ! COH
             !
             selfenergy(pstate,qstate,ispin) = selfenergy(pstate,qstate,ispin) &
                        - bra(ipole,pstate) * bra(ipole,qstate) & 
                              / wpol%pole(ipole)                &
                              * alpha_cohsex
           enddo
         enddo

       case default 
         call die('BUG')
       end select

     enddo !ipole

   enddo !istate
 enddo !ispin

 ! Sum up the contribution from different poles (= different procs)
 call xsum_ortho(selfenergy)


 ! Kotani's hermitianization trick
 call apply_qs_approximation(basis%nbf,nstate,s_matrix,c_matrix,selfenergy)


 call clean_deallocate('Temporary array',bra)

 if(has_auxil_basis) call destroy_eri_3center_eigen()


 call stop_clock(timing_self)


end subroutine gw_selfenergy_qs


!=========================================================================