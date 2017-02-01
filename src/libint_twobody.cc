/*
 * This file is part of MOLGW.
 * C/C++ wrapper to the libint library
 * two-body terms: 2-center Coulomb
 * with contracted gaussians
 * Author: F. Bruneval
 */
#include<libint2.h>
#include<stdlib.h>
#include<stdio.h>
#include<iostream>
#include<math.h>
#include<assert.h>
using namespace std;


/* Headers */
int nint(int am);
extern "C" void boys_function_c(double*, int, double);

/* Code */


/* ==========================================================================                    
 *                           2-center integrals
 * ========================================================================== */

#ifdef HAVE_LIBINT_2CENTER
extern "C" {
void libint_2center(int amA, int contrdepthA , double A [] , double alphaA [], double cA [], 
                    int amC, int contrdepthC , double C [] , double alphaC [], double cC [],
                    double rcut,
                    double eriAC [] ) {

 const unsigned int contrdepth2 = contrdepthA * contrdepthC;
 Libint_2eri_t* inteval = libint2::malloc<Libint_2eri_t>(contrdepth2);

 assert(amA <= LIBINT2_MAX_AM_eri);
 assert(amC <= LIBINT2_MAX_AM_eri);

#ifndef LIBINT2_CONTRACTED_INTS
 assert( contrdepthA == 1 );
 assert( contrdepthC == 1 );
#endif

 const unsigned int ammax = LIBINT2_MAX_AM_eri ;
 const int am = amA + amC ;


 LIBINT2_PREFIXED_NAME(libint2_init_2eri)(inteval, ammax, 0);

 Libint_2eri_t* int12 ;
 double alphaP, alphaQ ;
 double P[3], Q[3] ;
 double U ;
 double F[am+1] ;
 double gammapq ;
 double gammapq_rc2 ;
 double gammapq_ratio ;
 double PQx ;
 double PQy ;
 double PQz ;
 double PQ2 ;
 double Wx ;
 double Wy ;
 double Wz ;
 double pfac ;
 constexpr double pi_2p5 = pow(M_PI,2.5) ;

// for(int i=0;i<am+1;++i) F[i] = 0. ;

 int icontrdepth2 = 0 ;
 for( int icontrdepthA=0; icontrdepthA < contrdepthA; icontrdepthA++)  {
   for( int icontrdepthC=0; icontrdepthC < contrdepthC; icontrdepthC++)  {

     int12 = &inteval[icontrdepth2] ;
     alphaP = alphaA[icontrdepthA] ;
     alphaQ = alphaC[icontrdepthC] ;
     P[0] = A[0] ;
     P[1] = A[1] ;
     P[2] = A[2] ;

     int12->PA_x[0] = 0 ;
     int12->PA_y[0] = 0 ;
     int12->PA_z[0] = 0 ;
     int12->PB_x[0] = 0 ;
     int12->PB_y[0] = 0 ;
     int12->PB_z[0] = 0 ;
     int12->AB_x[0] = 0 ;
     int12->AB_y[0] = 0 ;
     int12->AB_z[0] = 0 ;
     int12->oo2z[0] = 0.5 / alphaP ;

     gammapq = alphaP * alphaQ / (alphaP + alphaQ);

/*
  Treat the LR integrals by simply modifying gammapq into gammapq_rc2
  And introducing gammapq_ratio = gammapq_rc2 / gammapq
 */

     gammapq_rc2   =   alphaP * alphaQ   / ( alphaP + alphaQ + alphaP * alphaQ * rcut * rcut );
     gammapq_ratio = ( alphaP + alphaQ ) / ( alphaP + alphaQ + alphaP * alphaQ * rcut * rcut );


     int12->QC_x[0] = 0 ;
     int12->QC_y[0] = 0 ;
     int12->QC_z[0] = 0 ;
/*
     int12->QD_x[0] = 0 ;
     int12->QD_y[0] = 0 ;
     int12->QD_z[0] = 0 ;
*/
     int12->CD_x[0] = 0 ;
     int12->CD_y[0] = 0 ;
     int12->CD_z[0] = 0 ;
     int12->oo2e[0] = 0.5 / alphaQ;

  // Prefactors for interelecttron transfer relation
#if LIBINT2_DEFINED(eri,TwoPRepITR_pfac0_0_x)
     int12->TwoPRepITR_pfac0_0_x[0] = 0 ; 
#endif
#if LIBINT2_DEFINED(eri,TwoPRepITR_pfac0_0_y)
     int12->TwoPRepITR_pfac0_0_y[0] = 0 ;
#endif
#if LIBINT2_DEFINED(eri,TwoPRepITR_pfac0_0_z)
     int12->TwoPRepITR_pfac0_0_z[0] = 0 ;
#endif
#if LIBINT2_DEFINED(eri,TwoPRepITR_pfac0_1_x)
     int12->TwoPRepITR_pfac0_1_x[0] = 0 ;
#endif
#if LIBINT2_DEFINED(eri,TwoPRepITR_pfac0_1_y)
     int12->TwoPRepITR_pfac0_1_y[0] = 0 ;
#endif
#if LIBINT2_DEFINED(eri,TwoPRepITR_pfac0_1_z)
     int12->TwoPRepITR_pfac0_1_z[0] = 0 ;
#endif
#if LIBINT2_DEFINED(eri,TwoPRepITR_pfac1_0)
     int12->TwoPRepITR_pfac1_0[0] = -alphaQ / alphaP;
#endif
#if LIBINT2_DEFINED(eri,TwoPRepITR_pfac1_1)
     int12->TwoPRepITR_pfac1_1[0] = -alphaP / alphaQ;
#endif

     PQx = A[0] - C[0];
     PQy = A[1] - C[1];
     PQz = A[2] - C[2];
     PQ2 = PQx * PQx + PQy * PQy + PQz * PQz;
     Wx = (alphaP * A[0] + alphaQ * C[0]) / (alphaP + alphaQ);
     Wy = (alphaP * A[1] + alphaQ * C[1]) / (alphaP + alphaQ);
     Wz = (alphaP * A[2] + alphaQ * C[2]) / (alphaP + alphaQ);

     int12->WP_x[0] = Wx - A[0];
     int12->WP_y[0] = Wy - A[1];
     int12->WP_z[0] = Wz - A[2];
     int12->WQ_x[0] = Wx - C[0];
     int12->WQ_y[0] = Wy - C[1];
     int12->WQ_z[0] = Wz - C[2];
     int12->oo2ze[0] = 0.5 / ( alphaP + alphaQ ) ;
#if LIBINT2_DEFINED(eri,roz)
     int12->roz[0] = gammapq/alphaP;
#endif
#if LIBINT2_DEFINED(eri,roe)
     int12->roe[0] = gammapq/alphaQ;
#endif

     pfac = 2 * pi_2p5 / (alphaP * alphaQ * sqrt(alphaP + alphaQ)) * cA[icontrdepthA] * cC[icontrdepthC] ;
     U = PQ2 * gammapq_rc2 ;
   
     boys_function_c(F, am, U);

  // using dangerous macros from libint2.h
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(0))
     int12->LIBINT_T_SS_EREP_SS(0)[0] = pfac*F[0] * pow(gammapq_ratio,0.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(1))
     if( am > 0 ) int12->LIBINT_T_SS_EREP_SS(1)[0] = pfac*F[1] * pow(gammapq_ratio,1.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(2))
     if( am > 1 ) int12->LIBINT_T_SS_EREP_SS(2)[0] = pfac*F[2] * pow(gammapq_ratio,2.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(3))
     if( am > 2 ) int12->LIBINT_T_SS_EREP_SS(3)[0] = pfac*F[3] * pow(gammapq_ratio,3.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(4))
     if( am > 3 ) int12->LIBINT_T_SS_EREP_SS(4)[0] = pfac*F[4] * pow(gammapq_ratio,4.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(5))
     if( am > 4 ) int12->LIBINT_T_SS_EREP_SS(5)[0] = pfac*F[5] * pow(gammapq_ratio,5.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(6))
     if( am > 5 ) int12->LIBINT_T_SS_EREP_SS(6)[0] = pfac*F[6] * pow(gammapq_ratio,6.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(7))
     if( am > 6 ) int12->LIBINT_T_SS_EREP_SS(7)[0] = pfac*F[7] * pow(gammapq_ratio,7.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(8))
     if( am > 7 ) int12->LIBINT_T_SS_EREP_SS(8)[0] = pfac*F[8] * pow(gammapq_ratio,8.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(9))
     if( am > 8 ) int12->LIBINT_T_SS_EREP_SS(9)[0] = pfac*F[9] * pow(gammapq_ratio,9.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(10))
     if( am > 9 ) int12->LIBINT_T_SS_EREP_SS(10)[0] = pfac*F[10] * pow(gammapq_ratio,10.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(11))
     if( am > 10) int12->LIBINT_T_SS_EREP_SS(11)[0] = pfac*F[11] * pow(gammapq_ratio,11.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(12))
     if( am > 11) int12->LIBINT_T_SS_EREP_SS(12)[0] = pfac*F[12] * pow(gammapq_ratio,12.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(13))
     if( am > 12) int12->LIBINT_T_SS_EREP_SS(13)[0] = pfac*F[13] * pow(gammapq_ratio,13.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(14))
     if( am > 13) int12->LIBINT_T_SS_EREP_SS(14)[0] = pfac*F[14] * pow(gammapq_ratio,14.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(15))
     if( am > 14) int12->LIBINT_T_SS_EREP_SS(15)[0] = pfac*F[15] * pow(gammapq_ratio,15.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(16))
     if( am > 15) int12->LIBINT_T_SS_EREP_SS(16)[0] = pfac*F[16] * pow(gammapq_ratio,16.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(17))
     if( am > 16) int12->LIBINT_T_SS_EREP_SS(17)[0] = pfac*F[17] * pow(gammapq_ratio,17.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(18))
     if( am > 17) int12->LIBINT_T_SS_EREP_SS(18)[0] = pfac*F[18] * pow(gammapq_ratio,18.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(19))
     if( am > 18) int12->LIBINT_T_SS_EREP_SS(19)[0] = pfac*F[19] * pow(gammapq_ratio,19.5);
#endif
#if LIBINT2_DEFINED(eri,LIBINT_T_SS_EREP_SS(20))
     if( am > 19) int12->LIBINT_T_SS_EREP_SS(20)[0] = pfac*F[20] * pow(gammapq_ratio,20.5);
#endif


     int12->_0_Overlap_0_x[0] = 0.0 ;
     int12->_0_Overlap_0_y[0] = 0.0 ;
     int12->_0_Overlap_0_z[0] = 0.0 ;
 
     int12->veclen = 1 ;
     int12->contrdepth = contrdepth2 ;

     icontrdepth2++ ;
   }
 }




 if( am == 0 ) {

   eriAC[0] = 0.0 ;
   for( int icontrdepth2=0; icontrdepth2 < contrdepth2; icontrdepth2++) {
     eriAC[0] +=  inteval[icontrdepth2].LIBINT_T_SS_EREP_SS(0)[0] ;
   }

 } else {

   LIBINT2_PREFIXED_NAME(libint2_build_2eri)[amA][amC](inteval);
   for( int i12=0; i12 < nint(amA) * nint(amC) ; ++i12 ) {
     eriAC[i12] = inteval[0].targets[0][i12] ;
   }
 }



 LIBINT2_PREFIXED_NAME(libint2_cleanup_2eri)(inteval);

}
}



#endif

