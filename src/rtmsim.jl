# RTMsim - A Julia module for filling simulations in Resin Transfer Moulding with the Finite Area Method
# 
# Documentation: https://obertscheiderfhwn.github.io/RTMsim/build/
# Repository: https://github.com/obertscheiderfhwn/RTMsim
#
module rtmsim
    using Glob, LinearAlgebra, JLD2, GeometryBasics, GLMakie, Makie, Random, FileIO, ProgressMeter, NativeFileDialog, Gtk.ShortNames, Gtk.GConstants, Gtk.Graphics, Gtk
    GLMakie.activate!()    
    #using MAT  #temporary output in Matlab mat-format
            
    """
        start_rtmsim(inputfilename)
        
    Reads the text input file and calls the solver with the read parameters. 

    Arguments:
    - inputfilename :: String
    
    The complete set of input parameters can be accessed in the input file. The following paragraph shows an example for such an input file:
    ```
        1    #i_model 
        meshfiles\\mesh_permeameter1_foursets.bdf    #meshfilename 
        200    #tmax 
        1.01325e5 1.225 1.4 0.06    #p_ref rho_ref gamma mu_resin_val 
        1.35e5 1.0e5    #p_a_val p_init_val 
        3e-3 0.7 3e-10 1 1 0 0    #t_val porosity_val K_val alpha_val refdir1_val refdir2_val refdir3_val 
        3e-3 0.7 3e-10 1 1 0 0    #t1_val porosity1_val K1_val alpha1_val refdir11_val refdir21_val refdir31_val 
        3e-3 0.7 3e-10 1 1 0 0    #t2_val porosity2_val K2_val alpha2_val refdir12_val refdir22_val refdir32_val
        3e-3 0.7 3e-10 1 1 0 0    #t3_val porosity3_val K3_val alpha3_val refdir13_val refdir23_val refdir33_val
        3e-3 0.7 3e-10 1 1 0 0    #t4_val porosity4_val K4_val alpha4_val refdir14_val refdir24_val refdir34_val 
        1 0 0 0    #patchtype1val patchtype2val patchtype3val patchtype4val 
        0 results.jld2    #i_restart restartfilename
        0 0.01    #i_interactive r_p
        16    #n_pics
    ```

    Meaning of the variables:
    - `i_model`: Identifier for physical model (Default value is 1)
    - `meshfilename`: Mesh filename.
    - `tmax`: Maximum simulation time.
    - `p_ref rho_ref gamma mu_resin_val`: Parameters for the adiabatic equation of state and dynamic viscosity of resin used in the Darcy term.
    - `p_a_val p_init_val `: Absolut pressure value for injection port and for initial cavity pressure.
    - `t_val porosity_val K_val alpha_val refdir1_val refdir2_val refdir3_val`: Properties of the cells in the main preform: The vector `(refdir1_val,refdir2_val,refdir3_val)` is projected onto the cell in order to define the first principal cell direction. The second principal cell direction is perpendicular to the first one in the plane spanned by the cell nodes. The principal cell directions are used as the principal permeabilty directions. The cell properties are defined by the thickness `t_val`, the porosity `porosity_val`, the permeability `K_val` in the first principal cell direction, the permeablity `alpha_val` in the second principal direction.
    - `t1_val porosity1_val K1_val alpha1_val refdir11_val refdir21_val refdir31_val` etc.: Properties for up to four additional cell regions if preform. 
    - `patchtype1val patchtype2val patchtype3val patchtype4val`: These regions are used to specify the location of the pressure boundary conditions and to specify regions with different permeability, porosity and thickness properties (e.g. for different part thickness and layup or for race tracking which are regions with very high permeability typically at the boundary of the preforms). Vents need not be specified. Parameters `patchtype1val` define the patch type. Numerical values 0, 1, 2 and 3 are allowed with the following interpretation:
        - 0 .. the patch is ignored
        - 1 .. the patch represents an inlet gate, where the specified injection pressure level applies
        - 2 .. the patch specifies a preform region
        - 3 .. the patch represents a vent, where the specified initial pressure level applies
    - `i_restart restartfilename`: Start with new simulation if `0` or continue previous simulation if `1` from specified file
    - `i_interactive r_p`: Select the inlet ports graphically if i_interactive equal to `1` and inlet ports have specified radius
    - `n_pics`: Number of intermediate output files, supposed to be a multiple of `4`
    Entries are separated by one blank.

    Unit test:
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; inputfilename=joinpath(MODULE_ROOT,"inputfiles","input.txt"); rtmsim.start_rtmsim(inputfilename);`
    """
    function start_rtmsim(inputfilename)     
        if Sys.iswindows()
            inputfilename=replace(inputfilename,"/" => "\\")
        elseif Sys.islinux()
            inputfilename=replace(inputfilename,"\\" => "/")
        end        
        print("Read input file "*string(inputfilename)*"\n")
        if ~isfile(inputfilename)
            errorstring=string("File ",inputfilename," not existing"* "\n")
            error(errorstring)
        end
        i_model=[]; meshfilename=[]; tmax=[]
        p_ref=[]; rho_ref=[]; gamma=[]; mu_resin_val=[]; p_a_val=[]; p_init_val=[]
        t_val=[]; porosity_val=[]; K_val=[]; alpha_val=[]; refdir1_val=[]; refdir2_val=[]; refdir3_val=[]
        t1_val=[]; porosity1_val=[]; K1_val=[]; alpha1_val=[]; refdir11_val=[]; refdir21_val=[]; refdir31_val=[]
        t2_val=[]; porosity2_val=[]; K2_val=[]; alpha2_val=[]; refdir12_val=[]; refdir22_val=[]; refdir32_val=[]
        t3_val=[]; porosity3_val=[]; K3_val=[]; alpha3_val=[]; refdir13_val=[]; refdir23_val=[]; refdir33_val=[]
        t4_val=[]; porosity4_val=[]; K4_val=[]; alpha4_val=[]; refdir14_val=[]; refdir24_val=[]; refdir34_val=[]
        patchtype1val=[]; patchtype2val=[]; patchtype3val=[]; patchtype4val=[]
        i_restart=[]; restartfilename=[]; i_interactive=[]; r_p=[]; n_pics=[]
        open(inputfilename, "r") do fid
            i_line=1
            while !eof(fid)
                thisline=readline(fid)
                print(string(thisline)*"\n")
                txt1=split(thisline," ")
                if i_line==1            
                    i_model=parse(Int64,txt1[1])
                elseif i_line==2
                    meshfilename=txt1[1]
                    if Sys.iswindows()
                        meshfilename=replace(meshfilename,"/" => "\\")
                    elseif Sys.islinux()
                        meshfilename=replace(meshfilename,"\\" => "/")
                    end  
                elseif i_line==3
                    tmax=parse(Float64,txt1[1])
                elseif i_line==4
                    p_ref=parse(Float64,txt1[1])
                    rho_ref=parse(Float64,txt1[2])
                    gamma=parse(Float64,txt1[3])
                    mu_resin_val=parse(Float64,txt1[4])
                elseif i_line==5
                    p_a_val=parse(Float64,txt1[1])
                    p_init_val=parse(Float64,txt1[2])
                elseif i_line==6
                    t_val=parse(Float64,txt1[1])
                    porosity_val=parse(Float64,txt1[2])
                    K_val=parse(Float64,txt1[3])
                    alpha_val=parse(Float64,txt1[4])
                    refdir1_val=parse(Float64,txt1[5])
                    refdir2_val=parse(Float64,txt1[6])
                    refdir3_val=parse(Float64,txt1[7])
                elseif i_line==7
                    t1_val=parse(Float64,txt1[1])
                    porosity1_val=parse(Float64,txt1[2])
                    K1_val=parse(Float64,txt1[3])
                    alpha1_val=parse(Float64,txt1[4])
                    refdir11_val=parse(Float64,txt1[5])
                    refdir21_val=parse(Float64,txt1[6])
                    refdir31_val=parse(Float64,txt1[7])
                elseif i_line==8
                    t2_val=parse(Float64,txt1[1])
                    porosity2_val=parse(Float64,txt1[2])
                    K2_val=parse(Float64,txt1[3])
                    alpha2_val=parse(Float64,txt1[4])
                    refdir12_val=parse(Float64,txt1[5])
                    refdir22_val=parse(Float64,txt1[6])
                    refdir32_val=parse(Float64,txt1[7])
                elseif i_line==9        
                    t3_val=parse(Float64,txt1[1])
                    porosity3_val=parse(Float64,txt1[2])
                    K3_val=parse(Float64,txt1[3])
                    alpha3_val=parse(Float64,txt1[4])
                    refdir13_val=parse(Float64,txt1[5])
                    refdir23_val=parse(Float64,txt1[6])
                    refdir33_val=parse(Float64,txt1[7])
                elseif i_line==10
                    t4_val=parse(Float64,txt1[1])
                    porosity4_val=parse(Float64,txt1[2])
                    K4_val=parse(Float64,txt1[3])
                    alpha4_val=parse(Float64,txt1[4])
                    refdir14_val=parse(Float64,txt1[5])
                    refdir24_val=parse(Float64,txt1[6])
                    refdir34_val=parse(Float64,txt1[7])
                elseif i_line==11
                    patchtype1val=parse(Int64,txt1[1])
                    patchtype2val=parse(Int64,txt1[2])
                    patchtype3val=parse(Int64,txt1[3])
                    patchtype4val=parse(Int64,txt1[4])
                elseif i_line==12
                    i_restart=parse(Int64,txt1[1])
                    restartfilename=txt1[2]
                elseif i_line==13
                    i_interactive=parse(Int64,txt1[1])
                    r_p= parse(Float64,txt1[2])
                elseif i_line==14
                    n_pics=parse(Int64,txt1[1])
                end
                i_line=i_line+1
                if i_line==15
                    break
                end
            end
        end        
        print(" "*"\n")
        rtmsim_rev1(i_model,meshfilename,tmax,
            p_ref,rho_ref,gamma,mu_resin_val,
            p_a_val,p_init_val,
            t_val,porosity_val,K_val,alpha_val,refdir1_val,refdir2_val,refdir3_val,
            t1_val,porosity1_val,K1_val,alpha1_val,refdir11_val,refdir21_val,refdir31_val,
            t2_val,porosity2_val,K2_val,alpha2_val,refdir12_val,refdir22_val,refdir32_val,
            t3_val,porosity3_val,K3_val,alpha3_val,refdir13_val,refdir23_val,refdir33_val,
            t4_val,porosity4_val,K4_val,alpha4_val,refdir14_val,refdir24_val,refdir34_val,
            patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_restart,restartfilename,i_interactive,r_p,n_pics)
    end

    """
        rtmsim_rev1(i_model,meshfilename,tmax,
                    p_ref,rho_ref,gamma,mu_resin_val,
                    p_a_val,p_init_val,
                    t_val,porosity_val,K_val,alpha_val,refdir1_val,refdir2_val,refdir3_val,
                    t1_val,porosity1_val,K1_val,alpha1_val,refdir11_val,refdir21_val,refdir31_val,
                    t2_val,porosity2_val,K2_val,alpha2_val,refdir12_val,refdir22_val,refdir32_val,
                    t3_val,porosity3_val,K3_val,alpha3_val,refdir13_val,refdir23_val,refdir33_val,
                    t4_val,porosity4_val,K4_val,alpha4_val,refdir14_val,refdir24_val,refdir34_val,
                    patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_restart,restartfilename,i_interactive,r_p,n_pics)
    
    RTMsim solver with the following main steps:
    - Simulation initialization
    - Read mesh file and prepare patches  
    - Find neighbouring cells
    - Assign parameters to cells
    - Create local cell coordinate systems
    - Calculate initial time step
    - Array initialization
    - Define simulation time and intermediate output times
    - Boundary conditions
    - (Optional initialization if `i_model=2,3,..`)
    - Time evolution (for loops over all indices inside a while loop for time evolution)
        - Calculation of correction factors for cell thickness, porosity, permeability, viscosity
        - Pressure gradient calculation
        - Numerical flux function calculation
        - Update of rho, u, v, gamma and p according to conservation laws and equation of state
        - Boundary conditions
        - Prepare arrays for next time step
        - Saving of intermediate data
        - (Opional time marching etc. for i_model=2,3,...)
        - Calculation of adaptive time step 

    Arguments:
    - i_model :: Int
    - meshfile :: String
    - tmax :: Float
    - p_ref, rho_ref, gamma, mu_resin_val :: Float
    - t_val,porosity_val,K_val,alpha_val,refdir1_val,refdir2_val,refdir3_val :: Float
    - t1_val,porosity1_val,K1_val,alpha1_val,refdir11_val,refdir21_val,refdir31_val :: Float
    - t2_val,porosity2_val,K2_val,alpha2_val,refdir12_val,refdir22_val,refdir32_val :: Float
    - t3_val,porosity3_val,K3_val,alpha3_val,refdir13_val,refdir23_val,refdir33_val :: Float
    - t4_val,porosity4_val,K4_val,alpha4_val,refdir14_val,refdir24_val,refdir34_val :: Float
    - patchtype1val,patchtype2val,patchtype3val,patchtype4val :: Int
    - i_restart :: Int
    - restartfilename :: String
    - i_interactive :: Int64
    - r_p :: Float
    - n_pics :: Int

    Meaning of the variables:
    - `i_model`: Identifier for physical model (Default value is 1)
    - `meshfilename`: Mesh filename.
    - `tmax`: Maximum simulation time.
    - `p_ref rho_ref gamma mu_resin_val`: Parameters for the adiabatic equation of state and dynamic viscosity of resin used in the Darcy term.
    - `p_a_val p_init_val `: Absolut pressure value for injection port and for initial cavity pressure.
    - `t_val porosity_val K_val alpha_val refdir1_val refdir2_val refdir3_val`: Properties of the cells in the main preform: The vector `(refdir1_val,refdir2_val,refdir3_val)` is projected onto the cell in order to define the first principal cell direction. The second principal cell direction is perpendicular to the first one in the plane spanned by the cell nodes. The principal cell directions are used as the principal permeabilty directions. The cell properties are defined by the thickness `t_val`, the porosity `porosity_val`, the permeability `K_val` in the first principal cell direction, the permeablity `alpha_val` in the second principal direction.
    - `t1_val porosity1_val K1_val alpha1_val refdir11_val refdir21_val refdir31_val` etc.: Properties for up to four additional cell regions if preform. 
    - `patchtype1val patchtype2val patchtype3val patchtype4val`: These regions are used to specify the location of the pressure boundary conditions and to specify regions with different permeability, porosity and thickness properties (e.g. for different part thickness and layup or for race tracking which are regions with very high permeability typically at the boundary of the preforms). Vents need not be specified. Parameters `patchtype1val` define the patch type. Numerical values 0, 1, 2 and 3 are allowed with the following interpretation:
        - 0 .. the patch is ignored
        - 1 .. the patch represents an inlet gate, where the specified injection pressure level applies
        - 2 .. the patch specifies a preform region
        - 3 .. the patch represents a vent, where the specified initial pressure level applies
    - `i_restart restartfilename`: Start with new simulation if `0` or continue previous simulation if `1` from specified file
    - `i_interactive r_p`: Select the inlet ports graphically if i_interactive equal to `1` and inlet ports have specified radius
    - `n_pics`: Number of intermediate output files, supposed to be a multiple of `4`

    Unit tests:
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); rtmsim.rtmsim_rev1(1,meshfilename,200, 101325,1.225,1.4,0.06, 1.35e5,1.00e5, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-11,1,1,0,0, 3e-3,0.7,3e-11,1,1,0,0, 3e-3,0.7,3e-9,1,1,0,0, 1,2,2,2,0,"results.jld2",0,0.01,16)`
        
    Addtional unit tests:
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); rtmsim.rtmsim_rev1(1,meshfilename,200, 101325,1.225,1.4,0.06, 1.35e5,1.00e5, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-11,1,1,0,0, 3e-3,0.7,3e-11,1,1,0,0, 3e-3,0.7,3e-9,1,1,0,0, 1,0,0,0, 0,"results.jld2",0,0.01,16)` for starting a simulation with one pressure inlet port (sets 2, 3 and 4 are not used and consequently the preform parameters are ignored; since set 1 is a pressure inlet, also the parameters for set 1 are ignored and the only relevant parameter for the specified set is the pressure difference between injection and initial cavity pressure)
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); rtmsim.rtmsim_rev1(1,meshfilename,200, 101325,1.225,1.4,0.06, 1.35e5,1.00e5, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-11,1,1,0,0, 3e-3,0.7,3e-11,1,1,0,0, 3e-3,0.7,3e-9,1,1,0,0, 1,2,2,2, 0,"results.jld2",0,0.01,16)` for starting a simulation with different patches and race tracking
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); rtmsim.rtmsim_rev1(1,meshfilename,200, 101325,1.225,1.4,0.06, 1.35e5,1.00e5, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-11,1,1,0,0, 3e-3,0.7,3e-11,1,1,0,0, 3e-3,0.7,3e-9,1,1,0,0, 1,2,2,2, 1,"results.jld2",0,0.01,16)` for continuing the previous simulation   
    """
    function rtmsim_rev1(i_model,meshfilename,tmax,
        p_ref,rho_ref,gamma,mu_resin_val,
        p_a_val,p_init_val,
        t_val,porosity_val,K_val,alpha_val,refdir1_val,refdir2_val,refdir3_val,
        t1_val,porosity1_val,K1_val,alpha1_val,refdir11_val,refdir21_val,refdir31_val,
        t2_val,porosity2_val,K2_val,alpha2_val,refdir12_val,refdir22_val,refdir32_val,
        t3_val,porosity3_val,K3_val,alpha3_val,refdir13_val,refdir23_val,refdir33_val,
        t4_val,porosity4_val,K4_val,alpha4_val,refdir14_val,refdir24_val,refdir34_val,
        patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_restart,restartfilename,i_interactive,r_p,n_pics)
        
        if Sys.iswindows()
            meshfilename=replace(meshfilename,"/" => "\\")
        elseif Sys.islinux()
            meshfilename=replace(meshfilename,"\\" => "/")
        end  

        #----------------------------------------------------------------------
        # Simulation initialization
        #----------------------------------------------------------------------
        
        # Well defined variable types, except for strings meshfilename,restartfilename
        tmax=Float64(tmax)
        p_ref=Float64(p_ref);rho_ref=Float64(rho_ref);gamma=Float64(gamma);mu_resin_val=Float64(mu_resin_val)
        p_a_val=Float64(p_a_val);p_init_val=Float64(p_init_val)
        t_val=Float64(t_val);porosity_val=Float64(porosity_val);K_val=Float64(K_val);alpha_val=Float64(alpha_val);refdir1_val=Float64(refdir1_val);refdir2_val=Float64(refdir2_val);refdir3_val=Float64(refdir3_val)
        t1_val=Float64(t1_val);porosity1_val=Float64(porosity1_val);K1_val=Float64(K1_val);alpha1_val=Float64(alpha1_val);refdir11_val=Float64(refdir11_val);refdir21_val=Float64(refdir21_val);refdir31_val=Float64(refdir31_val)
        t2_val=Float64(t2_val);porosity2_val=Float64(porosity2_val);K2_val=Float64(K2_val);alpha2_val=Float64(alpha2_val);refdir12_val=Float64(refdir12_val);refdir22_val=Float64(refdir22_val);refdir32_val=Float64(refdir32_val)
        t3_val=Float64(t3_val);porosity3_val=Float64(porosity3_val);K3_val=Float64(K3_val);alpha3_val=Float64(alpha3_val);refdir13_val=Float64(refdir13_val);refdir23_val=Float64(refdir23_val);refdir33_val=Float64(refdir33_val)
        t4_val=Float64(t4_val);porosity4_val=Float64(porosity4_val);K4_val=Float64(K4_val);alpha4_val=Float64(alpha4_val);refdir14_val=Float64(refdir14_val);refdir24_val=Float64(refdir24_val);refdir34_val=Float64(refdir34_val)
        patchtype1val=Int64(patchtype1val);patchtype2val=Int64(patchtype2val);patchtype3val=Int64(patchtype3val);patchtype4val=Int64(patchtype4val)
        i_restart=Int64(i_restart);i_interactive=Int64(i_interactive);n_pics=Int64(n_pics)
 
        #License statement
        print("\n")
        println("RTMsim version 0.2")
        println("RTMsim is Julia code with GUI which simulates the mold filling in Liquid Composite Molding (LCM) manufacturing process.")
        println("Copyright (C) 2022 Christof Obertscheider / University of Applied Sciences Wiener Neustadt (FHWN)")
        println("")
        println("This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.")
        println("")
        println("This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.")
        println("")
        println("You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.")
        println("")
        println("This software is free of charge and may be used for commercial and academic purposes.  Please mention the use of this software at an appropriate place in your work.")
        println("")
        println("Submit bug reports to christof.obertscheider@fhwn.ac.at")
        println("")

        #Output simulation parameter overview
        println("")
        println("RTMsim started with the following parameters:")
        println("i_model=$(i_model)")
            if i_model!=1
                errorstring="Only iso-thermal RTM implemented, i.e. i_model must be =1 instead of = $(i_model)\n"
                error(errorstring)
            end
        println("meshfilename=$(meshfilename)")
            if ~isfile(meshfilename)
                errorstring="File $(meshfilename) not existing\n"
                error(errorstring);
            end
        println("tmax=$(tmax)")
            if tmax<=0.0
                errorstring="tmax must be greater than zero"
                error(errorstring)
            end
            #Limit number of results time steps between n_pics_min and n_pics_max and make it multiple of 4
            n_pics_input=n_pics
            n_pics_min = 4
            n_pics_max = 100
            if mod(n_pics,4)!=0
                n_pics=round(n_pics/4)*4
            end
            if n_pics<n_pics_min
                n_pics=n_pics_min
            end
            if n_pics>n_pics_max
                n_pics=n_pics_max 
            end       
            if n_pics>n_pics_max
                n_pics=n_pics_max
            end
            n_pics=Int64(n_pics)
        if n_pics_input!=n_pics
            println("n_pics changed to n_pics=$(n_pics)")
        else
            println("n_pics=$(n_pics)")
        end
        println("i_interactive=$(i_interactive)")
            if i_interactive!=0 && i_interactive!=1 && i_interactive!=2
                errorstring="Wrong value for i_interactive (must be=0,1,2)"
                error(errorstring)
            end 
        if i_restart==1
            println("i_restart, restartfilename=$(i_restart)") 
            if i_restart!=0 && i_restart!=1
                errorstring="Wrong value for i_restart (must be=0,1)"
                error(errorstring)
            end 
            if ~isfile(restartfilename)
                errorstring="File $(restartfilename) not existing\n" 
                error(errorstring);
            end
        end
        println("p_ref,rho_ref,gamma,mu=$(p_ref), $(rho_ref), $(gamma), $(mu_resin_val)")
        if p_ref<=0.0 || rho_ref<=0.0 || gamma<1.0 || mu_resin_val<=0.0
            errorstring="Wrong value for p_ref,rho_ref,gamma,mu (must be >0.0,>0.0,>1.0,>0.0)"
            error(errorstring)
        end 
        println("p_a_val,p_init_val=$(p_a_val), $(p_init_val)")
            if p_a_val<=p_init_val
                errorstring="Injection pressure must be greater than initial pressure"
                error(errorstring)
            end
            if p_a_val<=0.0 || p_init_val<0.0;
                errorstring="Wrong value for p_a_val,p_init_val (must be >0.0,>0.0)"
                error(errorstring)
            end 

        #Maximum number of cell neighbours
        maxnumberofneighbours=10

        #Delete old files and abort if meshfile is not existing
        if ~isfile(meshfilename)
            errorstring=string("File $(meshfilename) not existing\n") 
            error(errorstring)
        end
        if i_restart==1
            cp(restartfilename,"restart.jdl2";force=true)
        end
        delete_files()     
        if i_restart==1
            cp("restart.jdl2",restartfilename;force=true)
        end
        n_out=0.0

        #Assign and prepare physical parameters
        refdir_val=[refdir1_val,refdir2_val,refdir3_val]  #Vector
        u_a=0.0  
        u_b=0.0 
        u_init=0.0 
        v_a=0.0 
        v_b=0.0 
        v_init=0.0 
        p_a=p_a_val
        p_init=p_init_val
        p_b=p_a_val
        #Normalization for Delta p: p->p-p_init
            p_eps=100.0 #Float64(0.000e5); 
            p_a-=p_init+p_eps
            p_init=p_eps
            p_b=p_a-p_init+p_eps
            # p_ref=p_ref;  #p_ref-p_init+p_eps;
        kappa=p_ref/(rho_ref^gamma)
        #Lookuptable for adiabatic law (required for stability)
            p_int1=0.0; rho_int1=(p_int1/kappa)^(1/gamma)
            p_int2=10000.0; rho_int2=(p_int2/kappa)^(1/gamma)
            p_int3=0.5e5; rho_int3=(p_int3/kappa)^(1/gamma)
            p_int4=1.0e5; rho_int4=(p_int4/kappa)^(1/gamma)
            p_int5=1.0e6; rho_int5=(p_int5/kappa)^(1/gamma)
            p_int6=1.0e7; rho_int6=(p_int6/kappa)^(1/gamma)
            A=[rho_int1^2 rho_int1 1.0; rho_int3^2 rho_int3 1.0; rho_int4^2 rho_int4 1.0]
            b=[p_int1;p_int3;p_int4]
            apvals=A\b
            ap1=apvals[1];ap2=apvals[2];ap3=apvals[3];
        rho_a=(p_a/kappa)^(1/gamma)
        rho_b=(p_b/kappa)^(1/gamma)
        rho_init=(p_init/kappa)^(1/gamma)

        if gamma>=100;  #insert here coefficients for an incompressible EOS with resin mass density as rho_ref 
                        #at p_b and 0.9*rho_ref at p_a but the EOS is for deltap and consequently normalized pressure values
            #ap1=0;
            #ap2=(p_b-p_init)/(0.1*rho_ref);
            #ap3=p_b-(p_b-p_init)/0.1; 
            #rho_a=p_a/ap2-ap3/ap2;
            #rho_b=p_b/ap2-ap3/ap2;
            #rho_init=p_init/ap2-ap3/ap2;

            rho_a=rho_ref
            rho_b=rho_a
            rho_init=0.0
            p_int1=p_init; rho_int1=rho_init
            p_int2=p_init+0.9*(p_a-p_init); rho_int2=0.1*rho_a
            p_int3=p_a; rho_int3=rho_a
            #A=[rho_int1^2 rho_int1 Float64(1.0); rho_int2^2 rho_int2 Float64(1.0); rho_int3^2 rho_int3 Float64(1.0)];
            #b=[p_int1;p_int2;p_int3];
            A=[rho_int1^2 rho_int1 1.0; rho_int3^2 rho_int3 1.0; 2*rho_int3 1.0 0]
            b=[p_int1;p_int3;Float64(0.0)]
            apvals=A\b
            ap1=apvals[1];ap2=apvals[2];ap3=apvals[3]
            #ap1*rho_new[ind]^2+ap2*rho_new[ind]+ap3;


            println("rho_int1: $(rho_int1)")
            println("rho_int2: $(rho_int2)")
            println("rho_int3: $(rho_int3)")
            println("p_int1: $(p_int1)")
            println("p_int2: $(p_int2)")
            println("p_int3: $(p_int3)")
            
            println("ap1: $(ap1)")
            println("ap2: $(ap2)") 
            println("ap3: $(ap3)") 
            println("p_a: $(p_a)")
            println("p_b: $(p_b)")
            println("p_init: $(p_init)")
            println("rho_a: $(rho_a)")
            println("rho_b: $(rho_b)")
            println("rho_init: $(rho_init)")
        end
        
        T_a=295.0
        T_b=295.0
        T_init=295.0
        gamma_a=1.0
        gamma_b=1.0    
        gamma_init=0.0
        paramset=[porosity_val,t_val,K_val,alpha_val,refdir1_val,refdir2_val,refdir3_val]
        paramset1=[porosity1_val,t1_val,K1_val,alpha1_val,refdir11_val,refdir21_val,refdir31_val]
        paramset2=[porosity2_val,t2_val,K2_val,alpha2_val,refdir12_val,refdir22_val,refdir32_val]
        paramset3=[porosity3_val,t3_val,K3_val,alpha3_val,refdir13_val,refdir23_val,refdir33_val]
        paramset4=[porosity4_val,t4_val,K4_val,alpha4_val,refdir14_val,refdir24_val,refdir34_val]


        #--------------------------------------------------------------------------
        # Read mesh file and prepare patches     
        #--------------------------------------------------------------------------
        N,cellgridid,gridx,gridy,gridz,cellcenterx,cellcentery,cellcenterz,patchparameters,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchids1,patchids2,patchids3,patchids4,inletpatchids=
            read_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p);

        print(string("parameters for main preform: ",string(patchparameters) , "\n" ) );
        if patchparameters[1]<=0.0 || patchparameters[1]>1.0 || patchparameters[2]<=0.0 || patchparameters[3]<=0 || patchparameters[4]<=0;
            errorstring="Wrong value for porosity,thickness,permeability,alpha (must be between >0 and <=1,>0.0,>0.0,>0.0)"
            error(errorstring)
        end 
        if ~isempty(patchids1); 
            if patchtype1val==1;        
                print("patch 1 is pressure inlet \n"); 
            elseif patchtype1val==2;        
                print(string("parameters for patch 1: ",string(patchparameters1), "\n" ) );
                if patchparameters1[1]<=0.0 || patchparameters1[1]>1.0 || patchparameters1[2]<=0.0 || patchparameters1[3]<=0 || patchparameters1[4]<=0;
                    errorstring="Wrong value for porosity,thickness,permeability,alpha (must be between >0 and <=1,>0.0,>0.0,>0.0)"
                    error(errorstring)
                end 
            elseif patchtype1val==3;        
                print("patch 1 is pressure outlet \n"); 
            end
        end
        if ~isempty(patchids2); 
            if patchtype2val==1;        
                print("patch 4 is pressure inlet \n"); 
            elseif patchtype2val==2;        
                print(string("parameters for patch 2: ",string(patchparameters2), "\n" ) );
                if patchparameters2[1]<=0.0 || patchparameters2[1]>1.0 || patchparameters2[2]<=0.0 || patchparameters2[3]<=0 || patchparameters2[4]<=0;
                    errorstring="Wrong value for porosity,thickness,permeability,alpha (must be between >0 and <=1,>0.0,>0.0,>0.0)"
                    error(errorstring)
                end 
            elseif patchtype2val==3;        
                print("patch 2 is pressure outlet \n"); 
            end
        end
        if ~isempty(patchids3); 
            if patchtype3val==1;        
                print("patch 3 is pressure inlet \n"); 
            elseif patchtype3val==2;        
                print(string("parameters for patch 3: ",string(patchparameters3), "\n" ) );
                if patchparameters3[1]<=0.0 || patchparameters3[1]>1.0 || patchparameters3[2]<=0.0 || patchparameters3[3]<=0 || patchparameters3[4]<=0;
                    errorstring="Wrong value for porosity,thickness,permeability,alpha (must be between >0 and <=1,>0.0,>0.0,>0.0)"
                    error(errorstring)
                end 
            elseif patchtype3val==3;        
                print("patch 3 is pressure outlet \n"); 
            end
        end
        if ~isempty(patchids4); 
            if patchtype4val==1;        
                print("patch 4 is pressure inlet \n"); 
            elseif patchtype4val==2;        
                print(string("parameters for patch 4: ",string(patchparameters4),"\n" ) );
                if patchparameters4[1]<=0.0 || patchparameters4[1]>1.0 || patchparameters4[2]<=0.0 || patchparameters4[3]<=0 || patchparameters4[4]<=0;
                    errorstring="Wrong value for porosity,thickness,permeability,alpha (must be between >0 and <=1,>0.0,>0.0,>0.0)"
                    error(errorstring)
                end 
            elseif patchtype4val==3;        
                print("patch 4 is pressure outlet \n");   
            end
        end
        if patchtype1val!=1 && patchtype2val!=1 && patchtype3val!=1 && patchtype3val!=1 && i_interactive==0 && i_restart==0
            errorstring=string("No inlet defined" * "\n"); 
            error(errorstring);
        end
        if i_interactive==1 || i_interactive==2;
            print("additional inlet defined interactively \n");   
        end

        #--------------------------------------------------------------------------
        #  Find neighbouring cells
        #--------------------------------------------------------------------------    
        faces,cellneighboursarray,celltype = 
            create_faces(cellgridid, N, maxnumberofneighbours);


        #--------------------------------------------------------------------------
        #  Assign parameters to cells
        #--------------------------------------------------------------------------             
        cellthickness, cellporosity, cellpermeability, cellalpha, celldirection, cellviscosity, celltype = 
            assign_parameters(i_interactive,celltype,patchparameters,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,patchids1,patchids2,patchids3,patchids4,inletpatchids,mu_resin_val,N);


        #--------------------------------------------------------------------------    
        #  Create local cell coordinate systems
        #--------------------------------------------------------------------------    
        cellvolume, cellcentertocellcenterx, cellcentertocellcentery, T11, T12, T21, T22, cellfacenormalx, cellfacenormaly, cellfacearea = 
            create_coordinate_systems(N, cellgridid, gridx, gridy, gridz, cellcenterx,cellcentery,cellcenterz, faces, cellneighboursarray, celldirection, cellthickness,maxnumberofneighbours);


        #----------------------------------------------------------------------
        # Initial time step calculation
        #----------------------------------------------------------------------
        area=minimum(cellvolume./cellthickness);
        maxspeed=max(maximum(cellpermeability./cellviscosity),maximum(cellalpha.*cellpermeability./cellviscosity))*(p_a_val-p_init_val)/minimum(cellvolume./cellthickness);  #sqrt(area);
        betat1=1;
        deltat=betat1*sqrt(area)/maxspeed;
        deltat_initial=deltat;


        #----------------------------------------------------------------------
        # Array initialization
        #----------------------------------------------------------------------
        rho_old=Vector{Float64}(undef, N);
        u_old=Vector{Float64}(undef, N);
        v_old=Vector{Float64}(undef, N);
        p_old=Vector{Float64}(undef, N);
        gamma_old=Vector{Float64}(undef, N);
        rho_new=Vector{Float64}(undef, N);
        u_new=Vector{Float64}(undef, N);
        v_new=Vector{Float64}(undef, N);
        p_new=Vector{Float64}(undef, N);
        gamma_new=Vector{Float64}(undef, N);
        gamma_out=Vector{Float64}(undef, N);
        for ind in 1:N;
            u_old[ind]=u_init;
            v_old[ind]=v_init;
            rho_old[ind]=rho_init;
            p_old[ind]=p_init;
            gamma_old[ind]=gamma_init;
        end
        for ind in 1:N
            u_new[ind]=-9e9;
            v_new[ind]=-9e9;
            rho_new[ind]=-9e9;
            p_new[ind]=-9e9;
            gamma_new[ind]=-9e9;
            gamma_out[ind]=-9e9;
        end        
        thickness_factor=Vector{Float64}(undef, N);
        volume_factor=Vector{Float64}(undef, N);
        face_factor=Array{Float64}(undef, N, maxnumberofneighbours);
        porosity_factor=Vector{Float64}(undef, N);
        permeability_factor=Vector{Float64}(undef, N);
        viscosity_factor=Vector{Float64}(undef, N);

        if i_restart==1;
            if ~isfile(restartfilename);
                errorstring=string("File ",restartfilename," not existing"  * "\n"); 
                error(errorstring);
            end
            @load restartfilename t rho_new u_new v_new p_new gamma_new gamma_out gridx gridy gridz cellgridid N n_out
            u_old=u_new;
            v_old=v_new;
            rho_old=rho_new;
            p_old=p_new;
            gamma_old=gamma_new;
            t_restart=t;
        else 
            t_restart=0;
        end

        #----------------------------------------------------------------------
        # Define simulation time and intermediate output times
        #----------------------------------------------------------------------
        t_out=0;
        t_progressbar=0;
        t=0;
        tmin=n_pics*deltat;
        tmax=max(tmin,tmax);    

        #----------------------------------------------------------------------
        # Boundary conditions
        #----------------------------------------------------------------------
        for ind in 1:N;
            if celltype[ind]==-1;  #pressure boundary
                u_old[ind]=u_a;
                v_old[ind]=v_a;
                rho_old[ind]=rho_a;
                p_old[ind]=p_a;
                gamma_old[ind]=gamma_a;
            elseif celltype[ind]==-2;  #pressure outlet
                u_old[ind]=u_init;
                v_old[ind]=v_init;
                rho_old[ind]=rho_init;
                p_old[ind]=p_init;
                gamma_old[ind]=gamma_init;
            end
        end

        if i_model==2;
            #----------------------------------------------------------------------
            # Optional initialization if i_model=2,3,.. 
            #----------------------------------------------------------------------
            # -read text file with parameters
            # -array initialization
            # -boundary conditions
            # e.g. for vacuum infusion: Model for thickness, permeability and porosity change
            #      or temperature equation and degree of cure equation with modified viscosity
        end

        #Abort if no pressure inlet is defined, neither interactively nor as patch
        if i_restart==0;
            inds1=findall(isequal(-1),celltype);
            if isempty(inds1)
                errorstring="No pressure inlet ports defined";
                error(errorsting);
            end
        end

        #----------------------------------------------------------------------
        # Time evolution
        #----------------------------------------------------------------------
        n_progressbar=20;
        deltat_progressbar=tmax/n_progressbar;
        p=Progress(n_progressbar);
        iter=1;
        while t<=tmax;           
            for ind in 1:N 
                if i_model==1;
                    thickness_factor[ind]=Float64(1.0);  #change in cell thickness
                    volume_factor[ind]=Float64(1.0);  #change in cell volume do to cell thickness change
                    for i_neighbour in 1:maxnumberofneighbours
                        face_factor[ind,i_neighbour]=Float64(1.0);  #change is cell boundary area as average of the change in the two neighbouring cells
                    end
                    porosity_factor[ind]=Float64(1.0);  #change in porosity
                    permeability_factor[ind]=Float64(1.0);  #change in permeability
                    viscosity_factor[ind]=Float64(1.0);  #change in viscosity
                elseif i_model==2;
                    #Optional initialization if i_model=2,3,.. 
                end
            end

            for ind in 1:N
                if celltype[ind]==1  || celltype[ind]==-3; 
                    #Pressure gradient calculation
                    #dpdx,dpdy=numerical_gradient(1,ind,p_old,cellneighboursarray,cellcentertocellcenterx,cellcentertocellcentery);
                    dpdx,dpdy=numerical_gradient(3,ind,p_old,cellneighboursarray,cellcentertocellcenterx,cellcentertocellcentery);
                    
                    #FV scheme for rho,u,v,vof conservation laws
                    cellneighboursline=cellneighboursarray[ind,:];
                    cellneighboursline=cellneighboursline[cellneighboursline .> 0]
                    len_cellneighboursline=length(cellneighboursline)
                    F_rho_num=Float64(0.0);F_rho_num_add=Float64(0.0);
                    F_u_num=Float64(0.0);F_u_num_add=Float64(0.0);
                    F_v_num=Float64(0.0);F_v_num_add=Float64(0.0);
                    F_gamma_num=Float64(0.0);F_gamma_num_add=Float64(0.0);
                    F_gamma_num1=Float64(0.0);F_gamma_num1_add=Float64(0.0);
                    for i_neighbour=1:len_cellneighboursline;
                        i_P=ind;
                        i_A=cellneighboursarray[ind,i_neighbour];      
                        rho_P=rho_old[i_P];
                        rho_A=rho_old[i_A];
                        u_P=u_old[i_P];
                        v_P=v_old[i_P];
                        uvec=[T11[ind,i_neighbour] T12[ind,i_neighbour]; T21[ind,i_neighbour] T22[ind,i_neighbour]]*[u_old[i_A];v_old[i_A]];
                        u_A=uvec[1];
                        v_A=uvec[2];
                        gamma_P=gamma_old[i_P];
                        gamma_A=gamma_old[i_A];
                        A=cellfacearea[i_P,i_neighbour]*face_factor[i_P,i_neighbour];
                        n_x=cellfacenormalx[i_P,i_neighbour];
                        n_y=cellfacenormaly[i_P,i_neighbour];
                        vars_P=[rho_P,u_P,v_P,gamma_P];
                        vars_A=[rho_A,u_A,v_A,gamma_A];
                        if i_A>0 && (celltype[i_A]==1 || celltype[i_A]==-3);  #neighbour is inner or wall cell                            
                            meshparameters=[n_x,n_y,A];
                            F_rho_num_add,F_u_num_add,F_v_num_add,F_gamma_num_add,F_gamma_num1_add=numerical_flux_function(1,vars_P,vars_A,meshparameters);
                            F_rho_num=F_rho_num+F_rho_num_add;
                            F_u_num=F_u_num+F_u_num_add;
                            F_v_num=F_v_num+F_v_num_add;
                            F_gamma_num=F_gamma_num+F_gamma_num_add;
                            F_gamma_num1=F_gamma_num1+F_gamma_num1_add;  
                        end       
                        if i_A>0 && (celltype[i_A]==-1 || celltype[i_A]==-2);  #neighbour is pressure inlet or outlet
                            A=A*cellthickness[i_P]/(0.5*(cellthickness[i_P]+cellthickness[i_A]));
                            meshparameters=[n_x,n_y,A];
                            if celltype[i_A]==-2;  #pressure outlet
                                n_dot_u=dot([n_x; n_y],[u_P; v_P]);
                            elseif celltype[i_A]==-1;  #pressure inlet
                                n_dot_u=min(0,-1/(cellviscosity[i_P]*viscosity_factor[i_P])*dot([cellpermeability[i_P]*permeability_factor[i_P] 0; 0 cellalpha[i_P]*cellpermeability[i_P]*permeability_factor[ind]]*[dpdx;dpdy],[cellfacenormalx[i_P,i_neighbour];cellfacenormaly[i_P,i_neighbour]]));  #inflow according to Darcy's law and no backflow possible
                            end
                            F_rho_num_add,F_u_num_add,F_v_num_add,F_gamma_num_add,F_gamma_num1_add=numerical_flux_function_boundary(1,vars_P,vars_A,meshparameters,n_dot_u);
                            F_rho_num=F_rho_num+F_rho_num_add;
                            F_u_num=F_u_num+F_u_num_add;
                            F_v_num=F_v_num+F_v_num_add;
                            F_gamma_num=F_gamma_num+F_gamma_num_add;
                            F_gamma_num1=F_gamma_num1+F_gamma_num1_add; 
                        end      
                    end

                    rho_new[ind]=rho_old[ind]-deltat*F_rho_num/(cellvolume[ind]*volume_factor[ind]);
                    rho_new[ind]=max(rho_new[ind],0.0)
                    S_u=-dpdx;
                    u_new[ind]=(rho_old[ind]*u_old[ind]-deltat*F_u_num/(cellvolume[ind]*volume_factor[ind])+S_u*deltat)/(rho_new[ind]+(cellviscosity[ind]*viscosity_factor[ind])/(cellpermeability[ind]*permeability_factor[ind])*deltat);
                    S_v=-dpdy;
                    v_new[ind]=(rho_old[ind]*v_old[ind]-deltat*F_v_num/(cellvolume[ind]*volume_factor[ind])+S_v*deltat)/(rho_new[ind]+(cellviscosity[ind]*viscosity_factor[ind])/(cellalpha[ind]*cellpermeability[ind]*permeability_factor[ind])*deltat);   
                    gamma_new[ind]=((cellporosity[ind]*porosity_factor[ind])*gamma_old[ind]-deltat*(F_gamma_num-gamma_old[ind]*F_gamma_num1)/(cellvolume[ind]*volume_factor[ind]))/(cellporosity[ind]*porosity_factor[ind]); 
                    gamma_new[ind]=min(1,gamma_new[ind]);
                    gamma_new[ind]=max(0,gamma_new[ind]);
                    #EOS:
                    if gamma>1.01;
                       p_new[ind]=ap1*rho_new[ind]^2+ap2*rho_new[ind]+ap3;
                    else
                        p_new[ind]=kappa*rho_new[ind]^gamma;
                    end
                end
            end

            #boundary conditions, only for pressure boundary conditions
            for ind in 1:N;
                if celltype[ind]==-1;  #pressure inlet
                    u_new[ind]=u_a;
                    v_new[ind]=v_a;
                    rho_new[ind]=rho_a;
                    p_new[ind]=p_a;
                elseif celltype[ind]==-2;  #pressure outlet
                    u_new[ind]=u_init;
                    v_new[ind]=v_init;
                    rho_new[ind]=rho_init;
                    p_new[ind]=p_init;
                end
                if celltype[ind]==-1;  #pressure inlet
                    gamma_new[ind]=gamma_a;
                elseif celltype[ind]==-2;  #pressure outlet
                    gamma_new[ind]=gamma_init;
                end
            end 

            #prepare arrays for next time step
            u_old=u_new;
            v_old=v_new;
            rho_old=rho_new;
            p_old=p_new;
            gamma_old=gamma_new;

            #Progress bar with percentage during run
            prozent = (t/tmax)*100;  
            if t>=t_progressbar;
                #print(string(string(prozent),"%","\n"))
                t_progressbar=t_progressbar+deltat_progressbar;   
                next!(p);
            end      

            #Adaptive time stepping
            if iter>n_pics;
                inds1=findall(isequal(1),celltype);
                inds2=findall(isequal(-3),celltype);
                inds=vcat(inds1,inds2);               
                weight_deltatnew=Float64(0.5);  #0.1;  #
                if gamma>=100;
                    betat2=Float64(0.1*0.1);
                else
                    betat2=Float64(0.1);
                end
                deltat1=(1-weight_deltatnew)*deltat+weight_deltatnew* betat2*minimum( (sqrt.(cellvolume[inds]./cellthickness[inds])) ./ sqrt.(u_new[inds].^2+v_new[inds].^2) );  
                deltat=deltat1
                #deltat2=(1-weight_deltatnew)*deltat+weight_deltatnew* betat2*minimum( (sqrt.(cellvolume[inds]./cellthickness[inds])) ./ 340)  #sqrt.(gamma*p_new[inds]./rho_new[inds]) );  
                #deltat=min(deltat1,deltat2)  #minimum of convection and wave
                deltatmax=tmax/(4*n_pics); #at least four steps between writing output
                deltat=min(deltat,deltatmax);
            end

            #Save intermediate data
            if t>=t_out  || (t+deltat>tmax);
                if i_model==1;
                    if i_restart==1;
                        t_temp=t;
                        t=t+t_restart;
                    end
                    for i in 1:N
                        gamma_out[i]=gamma_new[i] 
                    end
                    inds=findall(isequal(-1),celltype); #if pressure inlet cells are present
                    for i in 1:length(inds)
                        gamma_out[inds[i]]=Float64(-1.0); 
                    end
                    inds=findall(isequal(-2),celltype); #if pressure outlet cells are present, they should not be plotted in the gamma-plot because not updated
                    for i in 1:length(inds)
                        gamma_out[inds[i]]=Float64(-2.0); 
                    end
                    if t>=(tmax+t_restart)-1.5*deltat;
                        t_temp1=t;
                        t=(tmax+t_restart);
                    end
                    outputfilename=string("output_", string(n_out), ".jld2")                
                    @save outputfilename t rho_new u_new v_new p_new gamma_new gamma_out gridx gridy gridz cellgridid N n_out
                    
                    #temporary output in Matlab mat-format
                    #outputfilename=string("output_", string(n_out), ".mat") 
                    #matwrite(outputfilename, Dict("t" => t,"rho_new" => rho_new,"u_new" => u_new,"v_new" => v_new,"p_new" => p_new,"gamma_new" => gamma_new,"gridx" => gridx,"gridy" => gridy,"gridz" => gridz,"cellgridid" => cellgridid,"N" => N,"n_out" => n_out))
                    
                    outputfilename=string("results.jld2")
                    @save outputfilename t rho_new u_new v_new p_new gamma_new gamma_out gridx gridy gridz cellgridid N n_out
                    if t>=(tmax+t_restart)-deltat;
                        t=t_temp1;
                    end                    
                    if i_restart==1;
                        t=t_temp;
                    end       
                end     
                n_out=n_out+1;
                t_out=t_out+tmax/n_pics;            
            end
            
            
            if i_model==2;
                #----------------------------------------------------------------------
                # Optional time marching etc. for i_model=2,3,.. 
                #----------------------------------------------------------------------
                # -for ind in 1:N loop with calculation of fluxes,...
                # -boundary conditions
                # -array preparation for next time step
                # -write save data to output files
            end

            iter=iter+1;
            t=t+deltat; 
        end
    end


    """
        function numerical_gradient(i_method,ind,p_old,cellneighboursarray,cellcentertocellcenterx,cellcentertocellcentery)
            
    Calculates the pressure gradient from the cell values of the neighbouring cells.
    - i_method=1 .. Least square solution to determine gradient
    - i_method=2 .. Least square solution to determine gradient with limiter
    - i_method=3 .. RUntime optimized least square solution to determine gradient

    Arguments:
    - i_method :: Int
    - ind :: Int
    - p_old :: Vector{Float}
    - cellneighoursarray :: Array{Float,2}
    - cellcentertocellcenterx, cellcentertocellcentery :: Array{Float,2}

    """
    function numerical_gradient(i_method,ind,p_old,cellneighboursarray,cellcentertocellcenterx,cellcentertocellcentery);
        if i_method==1;
            #least square solution to determine gradient
            cellneighboursline=cellneighboursarray[ind,:];
            cellneighboursline=cellneighboursline[cellneighboursline .> 0]
            len_cellneighboursline=length(cellneighboursline)
            bvec=Vector{Float64}(undef,len_cellneighboursline);
            Amat=Array{Float64}(undef,len_cellneighboursline,2);  
            for i_neighbour in 1:len_cellneighboursline;
                i_P=ind;
                i_A=cellneighboursarray[ind,i_neighbour];  
                Amat[i_neighbour,1]=cellcentertocellcenterx[ind,i_neighbour]
                Amat[i_neighbour,2]=cellcentertocellcentery[ind,i_neighbour]
                bvec[i_neighbour]=p_old[i_A]-p_old[i_P];
            end

            if len_cellneighboursline>1;
                xvec=Amat[1:len_cellneighboursline,:]\bvec[1:len_cellneighboursline];
                dpdx=xvec[1];
                dpdy=xvec[2];        
            else
                dpdx=0;
                dpdy=0;
            end
        elseif i_method==2;
            #least square solution to determine gradient with limiter
            cellneighboursline=cellneighboursarray[ind,:];
            cellneighboursline=cellneighboursline[cellneighboursline .> 0]
            len_cellneighboursline=length(cellneighboursline)
            bvec=Vector{Float64}(undef,len_cellneighboursline);
            Amat=Array{Float64}(undef,len_cellneighboursline,2);  
            wi=Vector{Float64}(undef,len_cellneighboursline);
            for i_neighbour in 1:len_cellneighboursline;
                i_P=ind;
                i_A=cellneighboursarray[ind,i_neighbour];  
                exp_limiter=2;
                wi[i_neighbour]=1/(sqrt((cellcentertocellcenterx[ind,i_neighbour])^2+(cellcentertocellcentery[ind,i_neighbour])^2))^exp_limiter;
                Amat[i_neighbour,1]=wi[i_neighbour]*cellcentertocellcenterx[ind,i_neighbour]
                Amat[i_neighbour,2]=wi[i_neighbour]*cellcentertocellcentery[ind,i_neighbour]
                bvec[i_neighbour]=wi[i_neighbour]*(p_old[i_A]-p_old[i_P]);
            end

            if len_cellneighboursline>1
                xvec=Amat[1:len_cellneighboursline,:]\bvec[1:len_cellneighboursline];
                dpdx=xvec[1];
                dpdy=xvec[2];            
            else
                dpdx=0;
                dpdy=0;
            end
        elseif i_method==3;
            #least square solution to determine gradient - runtime optimized
            cellneighboursline=cellneighboursarray[ind,:];
            cellneighboursline=cellneighboursline[cellneighboursline .> 0]
            len_cellneighboursline=length(cellneighboursline)
            bvec=Vector{Float64}(undef,len_cellneighboursline);
            Amat=Array{Float64}(undef,len_cellneighboursline,2);  
            for i_neighbour in 1:len_cellneighboursline;
                i_P=ind;
                i_A=cellneighboursarray[ind,i_neighbour];  
                Amat[i_neighbour,1]=cellcentertocellcenterx[ind,i_neighbour]
                Amat[i_neighbour,2]=cellcentertocellcentery[ind,i_neighbour]
                bvec[i_neighbour]=p_old[i_A]-p_old[i_P];
            end
            #xvec=Amat[1:len_cellneighboursline,:]\bvec[1:len_cellneighboursline];
            #dpdx=xvec[1];
            #dpdy=xvec[2];

            if len_cellneighboursline>1
                Aplus=transpose(Amat)*Amat;
                a=Aplus[1,1]
                b=Aplus[1,2]
                c=Aplus[2,1]
                d=Aplus[2,2] 
                bvec_mod=transpose(Amat)*bvec
                inv = 1/(a * d - b * c)
                # 1 / (ad -bc) * [d -b; -c a]
                dpdx = inv * d * bvec_mod[1] - inv * b * bvec_mod[2]
                dpdy = -inv * c * bvec_mod[1] + inv * a * bvec_mod[2]
            else
                dpdx=0;
                dpdy=0;
            end

        end
        return dpdx,dpdy
    end

    """
        function numerical_flux_function(i_method,vars_P,vars_A,meshparameters)

    Evaluates the numerical flux functions at the cell boundaries.
    - i_method==1 .. first order upwinding

    Arguments:
    - i_method :: Int
    - vars_P, vars_A :: 4-element Vector{Float}
    - meshparameters :: 3-element Vector{Float}
    """
    function numerical_flux_function(i_method,vars_P,vars_A,meshparameters);
        if i_method==1;
            #first order upwinding
            rho_P=vars_P[1];
            u_P=vars_P[2];
            v_P=vars_P[3];
            gamma_P=vars_P[4];
            rho_A=vars_A[1];
            u_A=vars_A[2];
            v_A=vars_A[3];
            gamma_A=vars_A[4];
            n_x=meshparameters[1];
            n_y=meshparameters[2];
            A=meshparameters[3];
            n_dot_rhou=dot([n_x; n_y],0.5*(rho_P+rho_A)*[0.5*(u_P+u_A); 0.5*(v_P+v_A)]);
            phi=1;
            F_rho_num_add=n_dot_rhou*phi*A;
            if n_dot_rhou>=0;
                phi=u_P;                                
            else
                phi=u_A;
            end
            F_u_num_add=n_dot_rhou*phi*A;     
            if n_dot_rhou>=0;
                phi=v_P;  
            else
                phi=v_A;
            end
            F_v_num_add=n_dot_rhou*phi*A; 
            n_dot_u=dot([n_x; n_y],[0.5*(u_P+u_A); 0.5*(v_P+v_A)]);
            if n_dot_u>=0; 
                phi=gamma_P;  
            else
                phi=gamma_A;
            end  
            F_gamma_num_add=n_dot_u*phi*A;
            phi=1;
            F_gamma_num1_add=n_dot_u*phi*A;
        end
        return F_rho_num_add,F_u_num_add,F_v_num_add,F_gamma_num_add,F_gamma_num1_add
    end

    """
        function numerical_flux_function_boundary(i_method,vars_P,vars_A,meshparameters,n_dot_u)

    Evaluates the numerical flux functions at the cell boundaries to pressure inlet or outlet.
    - i_method==1 .. first order upwinding

    Arguments:
    - i_method :: Int
    - vars_P, vars_A :: 4-element Vector{Float}
    - meshparameters :: 3-element Vector{Float}
    - n_dot_u :: Float
    """
    function numerical_flux_function_boundary(i_method,vars_P,vars_A,meshparameters,n_dot_u);
        if i_method==1;
            #first order upwinding
            rho_P=vars_P[1];
            u_P=vars_P[2];
            v_P=vars_P[3];
            gamma_P=vars_P[4];
            rho_A=vars_A[1];
            u_A=vars_A[2];
            v_A=vars_A[3];
            gamma_A=vars_A[4];
            n_x=meshparameters[1];
            n_y=meshparameters[2];
            A=meshparameters[3];        
            n_dot_rhou=n_dot_u*0.5*(rho_A+rho_P);
            phi=1;
            F_rho_num_add=n_dot_rhou*phi*A;
            if n_dot_u<=0 
                phi=u_A;                   
            else
                phi=u_P;
            end
            F_u_num_add=n_dot_rhou*phi*A;
            if n_dot_u<=0 
                phi=v_A;                   
            else
                phi=v_P;
            end
            F_v_num_add=n_dot_rhou*phi*A;
            if n_dot_u<=0 
                phi=gamma_A;                   
            else
                phi=gamma_P;
            end
            F_gamma_num_add=n_dot_u*phi*A;
            phi=1;
            F_gamma_num1_add=n_dot_u*phi*A;
        end
        return F_rho_num_add,F_u_num_add,F_v_num_add,F_gamma_num_add,F_gamma_num1_add
    end

    """
        function delete_files()
    
     Deletes the intermediate jld2 output files.
    """
    function delete_files();
        #delete the intermediate output files
        rm.(glob("output_*.jld2"))
    end

    """
        function read_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p)
    
    Read mesh file and prepare to be used in solver:
        - number of cells, cell ids start with 1
        - x,y,z-coordinates of the nodes
        - x,y,z-coordinates of the cell centers
        - patch properties
    Read other mesh files than Nastran bulk data format (bdf) based on extension and calculate the required mesh data or convert to Nastran format prepare with existing function                
    """
    function read_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p);

        #read Nastran mesh
        if meshfilename[end-2:end]=="bdf"
           N,cellgridid,gridx,gridy,gridz,cellcenterx,cellcentery,cellcenterz,patchparameters,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchids1,patchids2,patchids3,patchids4,inletpatchids=
                read_nastran_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p);
        end
   
        return N,cellgridid,gridx,gridy,gridz,cellcenterx,cellcentery,cellcenterz,patchparameters,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchids1,patchids2,patchids3,patchids4,inletpatchids
    end

    """
        function read_nastran_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p)

    Read file in Nastran format with fixed length (8 digits), nodes (`GRIDS`) defined in global coordinate system.

    Arguments:
    - meshfilename :: String
    - paramset, paramset1, paramset2, paramset3, paramset3 :: Vector{Float}
    - patchtype1val,patchtype1val1,patchtype1val2,patchtype1val3,patchtype1val4 :: Int
    - i_interactive :: Int
    - r_p :: Float

    Unit test:
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); paramset=[0.5,0.3,3e-10,1.0,1.0,0.0,0.0];paramset1=paramset;paramset2=paramset;paramset3=paramset;paramset4=paramset;patchtype1val=-1;patchtype2val=-1;patchtype3val=-1;patchtype4val=-1;i_interactive=0;r_p=0.01; N,cellgridid,gridx,gridy,gridz,cellcenterx,cellcentery,cellcenterz,patchparameters,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchids1,patchids2,patchids3,patchids4,inletpatchids=rtmsim.read_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p);`
    """
    function read_nastran_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p);

        if ~isfile(meshfilename);
            errorstring=string("File ",meshfilename," not existing"* "\n"); 
            error(errorstring);
        end
        ind=Int64(1);
        gridind=Int64(1);
        setind=Int64(1);
        issetdefinition=Int64(0);
        patchorigids1=[];
        patchorigids2=[];
        patchorigids3=[];
        patchorigids4=[];
        origgridid=[];
        gridx=[];
        gridy=[];
        gridz=[];
        celloriggridid=[];
        cellgridid=Array{Int64}(undef, 0, 3);
        inletpatchids=[];
        
        open(meshfilename, "r") do fid
            line=1;
            while !eof(fid)
                thisline=readline(fid)
                if length(thisline)>=8;
                    if issetdefinition==1; 
                        if cmp( thisline[1:8],"        ")!=0;  #check if the first eight characters are empty, else issetdefinition=0;
                             issetdefinition=Int64(0);
                             setind=setind+1;
                        end
                    end
                    card=thisline[1:8];
                    if cmp(card,"GRID    ")==0
                        gridindstring=thisline[9:16];
                        origgridid=vcat(origgridid,parse(Int64,gridindstring));                        
                        txt=thisline[25:32];
                        txt=replace(txt," "=> "");txt=replace(txt,"E" => "");txt=replace(txt,"e" => "");
                        txt1=replace(txt,"-" => "e-");txt1=replace(txt1,"+" => "e+");
                        if cmp(txt1[1],'e')==0;txt2=txt1[2:end];else;txt2=txt1;end;
                        val=parse(Float64,txt2);
                        val1=val;
                        txt=thisline[33:40];
                        txt=replace(txt," "=> "");txt=replace(txt,"E" => "");txt=replace(txt,"e" => "");
                        txt1=replace(txt,"-" => "e-");txt1=replace(txt1,"+" => "e+");
                        if cmp(txt1[1],'e')==0;txt2=txt1[2:end];else;txt2=txt1;end;
                        val=parse(Float64,txt2);
                        val2=val;
                        txt=thisline[41:48];
                        txt=replace(txt," "=> "");txt=replace(txt,"E" => "");txt=replace(txt,"e" => "");
                        txt1=replace(txt,"-" => "e-");txt1=replace(txt1,"+" => "e+");
                        if cmp(txt1[1],'e')==0;txt2=txt1[2:end];else;txt2=txt1;end;
                        val=parse(Float64,txt2);
                        val3=val;
                        gridx=vcat(gridx,Float64(val1));
                        gridy=vcat(gridy,Float64(val2));
                        gridz=vcat(gridz,Float64(val3));
                        gridind=gridind+1;
                    elseif cmp(card,"CTRIA3  ")==0;        
                        celloriggridid=vcat(celloriggridid,parse(Int64,thisline[9:16]));
                        i1val=parse(Int64,thisline[25:32]);
                        i1=findfirst(isequal(i1val),origgridid);
                        i2val=parse(Int64,thisline[33:40]);
                        i2=findfirst(isequal(i2val),origgridid);
                        i3val=parse(Int64,thisline[41:48]);
                        i3=findfirst(isequal(i3val),origgridid);
                        ivec=[i1,i2,i3];
                        idel=findall(isequal(min(ivec[1],ivec[2],ivec[3])),ivec);
                        deleteat!(ivec,idel)
                        idel=findall(isequal(max(ivec[1],ivec[2])),ivec);
                        deleteat!(ivec,idel)                        
                        cellgridid=vcat(cellgridid,[min(i1,i2,i3) ivec[1] max(i1,i2,i3)]);
                        ind=ind+1;    
                    elseif cmp( card[1:3],"SET")==0 || issetdefinition==1;
                        issetdefinition=1;
                        txt1=thisline[9:end];
                        txt1=replace(txt1," "=> "");
                        txt2=split(txt1,",");
                        for i in 1:length(txt2);
                            if !isempty(txt2[i]);
                                if setind==1; 
                                    patchorigids1=vcat(patchorigids1,parse(Int64,txt2[i]))
                                elseif setind==2;
                                    patchorigids2=vcat(patchorigids2,parse(Int64,txt2[i]))
                                elseif setind==3;
                                    patchorigids3=vcat(patchorigids3,parse(Int64,txt2[i]))
                                elseif setind==4;
                                    patchorigids4=vcat(patchorigids4,parse(Int64,txt2[i]))
                                end
                            end
                        end
                    end
                end
                line+=1
            end
        end
        N=ind-1;  #total number of cells
        
        #loop to define cell center coordinates in global CS
        cellcenterx=[];
        cellcentery=[];
        cellcenterz=[];
        for ind in 1:N;
            i1=cellgridid[ind,1];
            i2=cellgridid[ind,2];
            i3=cellgridid[ind,3];
            cellcenterx=vcat(cellcenterx,(gridx[i1]+gridx[i2]+gridx[i3])/3);
            cellcentery=vcat(cellcentery,(gridy[i1]+gridy[i2]+gridy[i3])/3);
            cellcenterz=vcat(cellcenterz,(gridz[i1]+gridz[i2]+gridz[i3])/3);
        end

        if i_interactive==1;
            assign_pset(r_p,N,cellcenterx,cellcentery,cellcenterz)
            psetfilename="pset.jld2"
            if ~isfile(psetfilename);
                errorstring=string("File ",psetfilename," not existing"* "\n"); 
                error(errorstring);
            end
            @load psetfilename pset;
            inletpatchids=pset;
            if length(inletpatchids)<1;
                errorstring=string("Inlet definition empty"* "\n"); 
                error(errorstring);
            end
            patchids1=[];
            patchids2=[];
            patchids3=[];
            patchids4=[];   
            patchparameters=paramset;
            patchparameters1=[];
            patchparameters2=[];
            patchparameters3=[];
            patchparameters4=[];        
        else
            patchids1=[];
            patchids2=[];
            patchids3=[];
            patchids4=[];
            for i in 1:length(patchorigids1);
                i1=findfirst(isequal(patchorigids1[i]),celloriggridid);
                patchids1=vcat(patchids1,i1);
            end
            for i=1:length(patchorigids2);
                i1=findfirst(isequal(patchorigids2[i]),celloriggridid);
                patchids2=vcat(patchids2,i1);
            end
            for i=1:length(patchorigids3);
                i1=findfirst(isequal(patchorigids3[i]),celloriggridid);
                patchids3=vcat(patchids3,i1);
            end
            for i=1:length(patchorigids4);
                i1=findfirst(isequal(patchorigids4[i]),celloriggridid);
                patchids4=vcat(patchids4,i1);
            end
            if i_interactive==2;
                assign_pset(r_p,N,cellcenterx,cellcentery,cellcenterz)
                psetfilename="pset.jld2"
                if ~isfile(psetfilename);
                    errorstring=string("File ",psetfilename," not existing"* "\n"); 
                    error(errorstring);
                end
                @load psetfilename pset;
                inletpatchids=pset;
                if length(patchids1)<1;
                    errorstring=string("Inlet definition empty"* "\n"); 
                    error(errorstring);
                end
            end
            patchparameters=paramset;
            patchparameters1=[];
            patchparameters2=[];
            patchparameters3=[];
            patchparameters4=[];
            for i_patch in 1:4;
                if i_patch==1;
                    patchids=patchids1;
                elseif i_patch==2;
                    patchids=patchids2;
                elseif i_patch==3;
                    patchids=patchids3;
                elseif i_patch==4;
                    patchids=patchids4;
                end
                if !isempty(patchids);
                    if i_patch==1;
                        if patchtype1val==2;
                            patchparameters1=paramset1;
                        end
                    elseif i_patch==2;
                        if patchtype2val==2;
                            patchparameters2=paramset2;
                        end
                    elseif i_patch==3;
                        if patchtype3val==2; 
                            patchparameters3=paramset3;
                        end
                    elseif i_patch==4;
                        if patchtype4val==2;
                            patchparameters4=paramset4;
                        end
                    end
                end
            end
        end
           
        return N,cellgridid,gridx,gridy,gridz,cellcenterx,cellcentery,cellcenterz,patchparameters,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchids1,patchids2,patchids3,patchids4,inletpatchids
    end


    """
        function create_faces(cellgridid, N, maxnumberofneighbours)

    Find the set with the IDs of the neighbouring cells and identify wall cells
    """
    function create_faces(cellgridid, N, maxnumberofneighbours);
        celltype=Vector{Int64}(undef, N);
        for i in 1:N;
            celltype[i]=1;
        end
        faces=Array{Int64}(undef, 0, 3);   #three columns: grid id1, grid id2, cell id
        i=1;
        for ind=1:N
            i1=cellgridid[ind,1];
            i2=cellgridid[ind,2];    
            faces=vcat(faces,[min(i1,i2) max(i1,i2) ind]);
            i=i+1;
            i1=cellgridid[ind,2];
            i2=cellgridid[ind,3];    
            faces=vcat(faces,[min(i1,i2) max(i1,i2) ind]);
            i=i+1;
            i1=cellgridid[ind,3];
            i2=cellgridid[ind,1];    
            faces=vcat(faces,[min(i1,i2) max(i1,i2) ind]);
            i=i+1;
        end
        facessorted=sortslices(faces,dims=1);
        vals1=unique(facessorted[:,1]);  

        # this must be generalized, currently only hard-coded number of neighbouring cells of a tria is possible
        # all considered cases had <<10 neighbouring cells 
        cellneighboursarray=Array{Int64}(undef, N, maxnumberofneighbours);
        for ind in 1:N;
            for ind_n in 1:maxnumberofneighbours;
                 cellneighboursarray[ind,ind_n]=-9;
            end
        end

        for i in 1:length(vals1);
            inds2=findall(isequal(vals1[i]), facessorted[:,1]);
            facesdetail_unsorted=facessorted[inds2,2:3];
            facesdetail=sortslices(facesdetail_unsorted,dims=1);
            for j=1:size(facesdetail,1);
                i1=facesdetail[j,2];
                inds3=findall(isequal(facesdetail[j,1]),facesdetail[:,1]);
                inds4=findall(!isequal(j),inds3);
                inds5=inds3[inds4];
                if isempty(inds5);
                    celltype[i1]=-3;  #wall
                else
                    if j==1;
                        for k in 1:length(inds5);
                            matrixrow=cellneighboursarray[i1,:];
                            indcolumn=findfirst(isequal(-9),matrixrow); 
                            if isnothing(indcolumn)
                                error("More than 10 neighbours of one tria is not supported \n");
                            else
                                cellneighboursarray[i1,indcolumn]=facesdetail[inds5[k],2];
                            end
                        end
                    else
                       for k in 1:1; 
                            matrixrow=cellneighboursarray[i1,:];
                            indcolumn=findfirst(isequal(-9),matrixrow); 
                            if isnothing(indcolumn)
                                error("More than 10 neighbours of one tria is not supported"* "\n");
                            else
                                cellneighboursarray[i1,indcolumn]=facesdetail[inds5[k],2];
                            end
                        end
                    end
                end
            end
        end

        return faces, cellneighboursarray, celltype
    end

    """
        function assign_parameters(i_interactive,celltype,patchparameters0,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,patchids1,patchids2,patchids3,patchids4,inletpatchids,mu_resin_val,N)
    
    Assign properties to cells.
    """
    function assign_parameters(i_interactive,celltype,patchparameters0,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,patchids1,patchids2,patchids3,patchids4,inletpatchids,mu_resin_val,N);
        cellthickness=Vector{Float64}(undef, N);
        cellporosity=Vector{Float64}(undef, N);
        cellpermeability=Vector{Float64}(undef, N);
        cellalpha=Vector{Float64}(undef, N);
        celldirection=Array{Float64}(undef, N,3);
        cellviscosity=Vector{Float64}(undef, N);

        if i_interactive==0 || i_interactive==2;
            if patchtype1val==1;
                for i in 1:N;
                    ind=findfirst(isequal(i),patchids1);
                    if ~isnothing(ind)
                        celltype[i]=-1;
                    end
                end                
            elseif patchtype1val==3;
                for i in 1:N;
                    ind=findfirst(isequal(i),patchids1);
                    if ~isnothing(ind)
                        celltype[i]=-2;
                    end
                end                  
            end
            if patchtype2val==1;
                for i in 1:N;
                    ind=findfirst(isequal(i),patchids2);
                    if ~isnothing(ind)
                        celltype[i]=-1;
                    end
                end
            elseif patchtype2val==3;
                for i in 1:N;
                    ind=findfirst(isequal(i),patchids2);
                    if ~isnothing(ind)
                        celltype[i]=-2;
                    end
                end
            end
            if patchtype3val==1;
                for i in 1:N;
                    ind=findfirst(isequal(i),patchids3);
                    if ~isnothing(ind)
                        celltype[i]=-1;
                    end
                end
            elseif patchtype3val==3;
                for i in 1:N;
                    ind=findfirst(isequal(i),patchids3);
                    if ~isnothing(ind)
                        celltype[i]=-2;
                    end
                end
            end
            if patchtype4val==1;
                for i in 1:N;
                    ind=findfirst(isequal(i),patchids4);
                    if ~isnothing(ind)
                        celltype[i]=-1;
                    end
                end
            elseif patchtype4val==3;
                for i in 1:N;
                    ind=findfirst(isequal(i),patchids4);
                    if ~isnothing(ind)
                        celltype[i]=-2;
                    end
                end
            end
        end
        if i_interactive==1 || i_interactive==2;
            for i in 1:N;
                ind=findfirst(isequal(i),inletpatchids);
                if ~isnothing(ind)
                    celltype[i]=-1;
                end
            end
        end        
        for ind in 1:N;
            if i_interactive==1;
                #thickness
                cellthickness[ind]=patchparameters0[2];
                #porosity
                cellporosity[ind]=patchparameters0[1]; 
                #isotropic permeability 
                cellpermeability[ind]=patchparameters0[3];            
                #alpha permeability 
                cellalpha[ind]=patchparameters0[4];
                #primary direction
                vec=[patchparameters0[5] patchparameters0[6] patchparameters0[7]];
                celldirection[ind,:]=vec/sqrt(dot(vec,vec));
                #viscosity
                cellviscosity[ind]=mu_resin_val; 
            else
                ind1=findfirst(isequal(ind),patchids1);
                ind2=findfirst(isequal(ind),patchids2);
                ind3=findfirst(isequal(ind),patchids3);
                ind4=findfirst(isequal(ind),patchids4);
                if (patchtype1val==2 && ~isnothing(ind1)) 
                    patchparameters=patchparameters1;
                elseif (patchtype2val==2 && ~isnothing(ind2)) 
                    patchparameters=patchparameters2;
                elseif (patchtype3val==2 && ~isnothing(ind3)) 
                    patchparameters=patchparameters3;
                elseif (patchtype4val==2 && ~isnothing(ind4)) 
                    patchparameters=patchparameters4;
                end
                if (patchtype1val==2 && issubset(ind,patchids1)) || (patchtype2val==2 && issubset(ind,patchids2)) || (patchtype3val==2 && issubset(ind,patchids3)) || (patchtype4val==2 && issubset(ind,patchids4));
                    #thickness
                    cellthickness[ind]=patchparameters[2];
                    #porosity
                    cellporosity[ind]=patchparameters[1]; 
                    #isotropic permeability 
                    cellpermeability[ind]=patchparameters[3];            
                    #alpha permeability 
                    cellalpha[ind]=patchparameters[4];
                    #primary direction
                    vec=[patchparameters[5] patchparameters[6] patchparameters[7]];
                    celldirection[ind,:]=vec/sqrt(dot(vec,vec));
                    #viscosity
                    cellviscosity[ind]=mu_resin_val; 
                else
                    #thickness
                    cellthickness[ind]=patchparameters0[2];
                    #porosity
                    cellporosity[ind]=patchparameters0[1]; 
                    #isotropic permeability 
                    cellpermeability[ind]=patchparameters0[3];            
                    #alpha permeability 
                    cellalpha[ind]=patchparameters0[4];
                    #primary direction
                    vec=[patchparameters0[5] patchparameters0[6] patchparameters0[7]];
                    celldirection[ind,:]=vec/sqrt(dot(vec,vec));
                    #viscosity
                    cellviscosity[ind]=mu_resin_val; 
                end
            end
        end

        return cellthickness, cellporosity, cellpermeability, cellalpha, celldirection, cellviscosity, celltype
    end

    """
        function create_coordinate_systems(N, cellgridid, gridx, gridy, gridz, cellcenterx,cellcentery,cellcenterz, faces, cellneighboursarray, celldirection, cellthickness, maxnumberofneighbours)

    Define the local cell coordinate system and the transformation matrix from the local cell coordinate system from the neighbouring cell to the local cell coordinate system of the considered cell
    """
    function create_coordinate_systems(N, cellgridid, gridx, gridy, gridz, cellcenterx,cellcentery,cellcenterz, faces, cellneighboursarray, celldirection, cellthickness, maxnumberofneighbours);
        cellvolume=Vector{Float64}(undef, N);
        cellcentertocellcenterx=Array{Float64}(undef, N, maxnumberofneighbours);
        cellcentertocellcentery=Array{Float64}(undef, N, maxnumberofneighbours);
        T11=Array{Float64}(undef, N, maxnumberofneighbours);
        T12=Array{Float64}(undef, N, maxnumberofneighbours);
        T21=Array{Float64}(undef, N, maxnumberofneighbours);
        T22=Array{Float64}(undef, N, maxnumberofneighbours);
        cellfacenormalx=Array{Float64}(undef, N, maxnumberofneighbours);
        cellfacenormaly=Array{Float64}(undef, N, maxnumberofneighbours);
        cellfacearea=Array{Float64}(undef, N, maxnumberofneighbours);
        for ind in 1:N;
            cellvolume[ind]=-9;
            for ind_n in 1:maxnumberofneighbours;
                cellcentertocellcenterx[ind,ind_n]=-9.0;
                cellcentertocellcentery[ind,ind_n]=-9.0;
                T11[ind,ind_n]=-9.0;
                T12[ind,ind_n]=-9.0;
                T21[ind,ind_n]=-9.0;
                T22[ind,ind_n]=-9.0;
                cellfacenormalx[ind,ind_n]=-9.0;
                cellfacenormaly[ind,ind_n]=-9.0;
                cellfacearea[ind,ind_n]=-9.0;
            end
        end
        b1=Array{Float64}(undef, N, 3);
        b2=Array{Float64}(undef, N, 3);
        b3=Array{Float64}(undef, N, 3);
        gridxlocal=Array{Float64}(undef, N, 3);
        gridylocal=Array{Float64}(undef, N, 3);
        gridzlocal=Array{Float64}(undef, N, 3);
        theta=Vector{Float64}(undef, N);

        for ind in 1:N;
            # First, an intermediate orthonormal basis {b1, b2, b3} is created with 
            # first direction pointing from node with smallest ID to node with medium ID, 
            # second direction pointing in the orthogonal component from node with smallest ID to node with highest ID and 
            # third direction given by the cross product of the first two directions. 
            # The origin of the local coordinate system is the geometric center of the triangular cell. 
            i1=cellgridid[ind,1];
            i2=cellgridid[ind,2];
            i3=cellgridid[ind,3];  
            b1[ind,1:3]=[gridx[i2]-gridx[i1] gridy[i2]-gridy[i1] gridz[i2]-gridz[i1]];
            b1[ind,1:3]=b1[ind,1:3]/sqrt(dot(b1[ind,1:3],b1[ind,1:3]));
            a2=[gridx[i3]-gridx[i1] gridy[i3]-gridy[i1] gridz[i3]-gridz[i1]]';
            a2=a2/sqrt(dot(a2,a2));
            b2[ind,1:3]=a2-dot(b1[ind,1:3],a2)/dot(b1[ind,1:3],b1[ind,1:3])*b1[ind,1:3];
            b2[ind,1:3]=b2[ind,1:3]/sqrt(dot(b2[ind,1:3],b2[ind,1:3]));
            b3[ind,1:3]=cross(b1[ind,1:3],b2[ind,1:3]);   

            # Then the reference vector is formulated in the intermediate orthonormal basis 
            Tmat=[b1[ind,1] b2[ind,1] b3[ind,1]; b1[ind,2] b2[ind,2] b3[ind,2]; b1[ind,3] b2[ind,3] b3[ind,3]];
            xvec=celldirection[ind,:];
            bvec=Tmat\xvec;
            r1=[bvec[1] bvec[2] bvec[3]]';  #ref dir in local CS

            # In order to get the local coordinate system the basis {b1, b2, b3} is rotated by angle theta about the b3-axis.
            # Calculate the angle by which b1 must be rotated about the b3-axis to match r1 via relation rotation matrix Rz(theta)*[1;0;0]=r1, i.e. cos(theta)=r1(1) and sin(theta)=r1(2);
            theta[ind]=atan(r1[2],r1[1]);
            #Rotation of theta about nvec=b3 to get c1 and c2 
            nvec=b3[ind,:];
            xvec=b1[ind,:];
            c1=nvec*dot(nvec,xvec)+cos(theta[ind])*cross(cross(nvec,xvec),nvec)+sin(theta[ind])*cross(nvec,xvec);
            xvec=b2[ind,:];
            c2=nvec*dot(nvec,xvec)+cos(theta[ind])*cross(cross(nvec,xvec),nvec)+sin(theta[ind])*cross(nvec,xvec);
            xvec=b3[ind,:];
            c3=nvec*dot(nvec,xvec)+cos(theta[ind])*cross(cross(nvec,xvec),nvec)+sin(theta[ind])*cross(nvec,xvec);
            b1[ind,:]=c1;
            b2[ind,:]=c2;
            b3[ind,:]=c3;  
        
            #transformation of vertices into local CS
            gridxlocal[ind,1]=gridx[i1]-cellcenterx[ind];
            gridylocal[ind,1]=gridy[i1]-cellcentery[ind];
            gridzlocal[ind,1]=gridz[i1]-cellcenterz[ind];
            gridxlocal[ind,2]=gridx[i2]-cellcenterx[ind];
            gridylocal[ind,2]=gridy[i2]-cellcentery[ind];
            gridzlocal[ind,2]=gridz[i2]-cellcenterz[ind];
            gridxlocal[ind,3]=gridx[i3]-cellcenterx[ind];
            gridylocal[ind,3]=gridy[i3]-cellcentery[ind];
            gridzlocal[ind,3]=gridz[i3]-cellcenterz[ind];
            Tmat=[b1[ind,1] b2[ind,1] b3[ind,1]; b1[ind,2] b2[ind,2] b3[ind,2]; b1[ind,3] b2[ind,3] b3[ind,3]];
            xvec=[gridxlocal[ind,1] gridylocal[ind,1] gridzlocal[ind,1]]'; 
            bvec=Tmat\xvec;
            gridxlocal[ind,1]=bvec[1];gridylocal[ind,1]=bvec[2];gridzlocal[ind,1]=bvec[3];
            xvec=[gridxlocal[ind,2] gridylocal[ind,2] gridzlocal[ind,2]]'; 
            bvec=Tmat\xvec;
            gridxlocal[ind,2]=bvec[1];gridylocal[ind,2]=bvec[2];gridzlocal[ind,2]=bvec[3];
            xvec=[gridxlocal[ind,3] gridylocal[ind,3] gridzlocal[ind,3]]'; 
            bvec=Tmat\xvec;
            gridxlocal[ind,3]=bvec[1];gridylocal[ind,3]=bvec[2];gridzlocal[ind,3]=bvec[3];
        end

        cellids=[Int64(-9) Int64(-9)];
        gridids=[Int64(-9) Int64(-9)];
        x=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        x0=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        r0=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        gridxlocal_neighbour=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        gridylocal_neighbour=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        gridzlocal_neighbour=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        f1=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        f2=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        f3=[Float64(-9.0), Float64(-9.0), Float64(-9.0)];
        # In a next step the flattened geometry is created, i.e. the cell center and
        # the non-common node of the neighbouring cell is rotated about
        # the common edge to lie in the plane of the considered cell with ID ind
        for ind in 1:N;
            cellneighboursline=cellneighboursarray[ind,:];
            cellneighboursline=cellneighboursline[cellneighboursline .> 0]
            for i_neighbour in 1:length(cellneighboursline);
                # Find first the cell center of neighbouring cell in local coordinate system of cell ind
                # 1) projection of cell center P=(0,0) onto straigth line through
                #    i1 and i2 to get point Q1 and calculation of length l1 of line
                #    segment PQ1
                # 2) projection of neighbouring cell center A onto straight line
                #    through i1 and i2 to get point Q2 in global coordinate system,
                #    calculatin of length l2 of segment AQ2 and then
                #    transformation of Q2 into local coordinate system and then
                #    cellcentertocellcenterx/y(ind,1) is given by vector addition
                #    PQ1+Q1Q2+l2/l1*PQ1
            
                #for every neighbour find the two indices belonging to the boundary
                #face in between; face direction is from smaller to larger index
                #x0..local coordinates of smaller index
                #r0..vector from smaller to larger index in LCS
                inds1=findall(isequal(ind),faces[:,3]);
                inds2=findall(isequal(cellneighboursline[i_neighbour]),faces[:,3]);
                mat1=faces[inds1,:];
                mat2=faces[inds2,:];
                mat3=vcat(mat1,mat2); 
                mat4=sortslices(mat3,dims=1);
                for irow in 1:size(mat4,1)-1;
                    if mat4[irow,1]==mat4[irow+1,1] && mat4[irow,2]==mat4[irow+1,2];
                        if mat4[irow,3]==ind
                            cellids=[ind mat4[irow+1,3]];
                        else
                            cellids=[ind mat4[irow,3]];
                        end
                        gridids=[mat4[irow,1] mat4[irow,2]];
                    end
                end
                inds=[cellgridid[ind,1], cellgridid[ind,2], cellgridid[ind,3]];
                ia=findall(isequal(gridids[1]),inds);
                ib=findall(isequal(gridids[2]),inds);
                x0=[gridxlocal[ind,ia], gridylocal[ind,ia], gridzlocal[ind,ia]];
                r0=[gridxlocal[ind,ib]-gridxlocal[ind,ia], gridylocal[ind,ib]-gridylocal[ind,ia], gridzlocal[ind,ib]-gridzlocal[ind,ia]];

                #Define xvec as the vector between cell centers ind and neighbouring cell center (A) (in GCS) 
                #and transform xvec into local coordinates bvec, this gives A in LCS.
                #Find normal distance from A in LCS to the cell boundary with that cell center A in flat geometry and 
                #face normal vector can be defined.
                x=[[0.0], [0.0], [0.0]];  #P at origin of local CS
                Px=x[1];
                Py=x[2];
                Pz=x[3];
                lambda=dot(x-x0,r0)/dot(r0,r0);  
                Q1x=x0[1]+lambda*r0[1];
                Q1y=x0[2]+lambda*r0[2];
                Q1z=x0[3]+lambda*r0[3];
                vec1=[Px-Q1x, Py-Q1y, Pz-Q1z];
                l1=sqrt(dot(vec1,vec1)); 
                nvec=[(Q1x-Px), (Q1y-Py), (Q1z-Pz)];
                nvec=nvec/sqrt(dot(nvec,nvec));
                cellfacenormalx[ind,i_neighbour]=only(nvec[1]);
                cellfacenormaly[ind,i_neighbour]=only(nvec[2]); 

                Tmat=[b1[ind,1] b2[ind,1] b3[ind,1]; b1[ind,2] b2[ind,2] b3[ind,2]; b1[ind,3] b2[ind,3] b3[ind,3]];
                xvec=[cellcenterx[cellneighboursarray[ind,i_neighbour]]-cellcenterx[ind], cellcentery[cellneighboursarray[ind,i_neighbour]]-cellcentery[ind], cellcenterz[cellneighboursarray[ind,i_neighbour]]-cellcenterz[ind] ];  #A in global CS
                bvec=Tmat\xvec;
                x=[[bvec[1]], [bvec[2]], [bvec[3]]]; #A in local CS
                Ax=x[1];
                Ay=x[2];
                Az=x[3];
                lambda=dot(x-x0,r0)/dot(r0,r0);
                Q2x=x0[1]+lambda*r0[1];
                Q2y=x0[2]+lambda*r0[2];
                Q2z=x0[3]+lambda*r0[3];
                vec2=[Ax-Q2x, Ay-Q2y, Az-Q2z];
                l2=sqrt(dot(vec2,vec2));
                cellcentertocellcenterx[ind,i_neighbour]=only(Px+(Q1x-Px)+(Q2x-Q1x)+l2/l1*(Q1x-Px));
                cellcentertocellcentery[ind,i_neighbour]=only(Py+(Q1y-Py)+(Q2y-Q1y)+l2/l1*(Q1y-Py));

                vec3=[gridxlocal[ind,ib]-gridxlocal[ind,ia], gridylocal[ind,ib]-gridylocal[ind,ia], gridzlocal[ind,ib]-gridzlocal[ind,ia]];
                cellfacearea[ind,i_neighbour]=0.5*(cellthickness[cellids[1]]+cellthickness[cellids[2]])*sqrt(dot(vec3,vec3));

                #Transformation matrix for (u,v) of neighbouring cells to local coordinate system.
                #Find the two common grid points and the third non-common grid point               
                ind21=-9;  #Issues with setdiff, therefore manual implementation  #setdiff(cellgridid[cellids[2],:],gridids)
                for ind_tmp in 1:3
                    if cellgridid[cellids[2],ind_tmp]!=gridids[1] && cellgridid[cellids[2],ind_tmp]!=gridids[2]
                        ind21=cellgridid[cellids[2],ind_tmp];
                    end
                end     
                thirdgrid=only(findall(isequal(ind21),cellgridid[cellids[2],:]));
                common1grid=only(findall(isequal(gridids[1]),cellgridid[cellids[2],:]));
                common2grid=only(findall(isequal(gridids[2]),cellgridid[cellids[2],:]));   
                #construction of the third one in outside normal direction for the flat geometry
                #based on the length of the two non-common edges
                gridxlocal_neighbour[2]=only(gridxlocal[ind,ia]);  #gridxlocal(ind,common1grid);
                gridxlocal_neighbour[3]=only(gridxlocal[ind,ib]);  #gridxlocal(ind,common2grid);
                gridylocal_neighbour[2]=only(gridylocal[ind,ia]);  #gridylocal(ind,common1grid);
                gridylocal_neighbour[3]=only(gridylocal[ind,ib]);  #gridylocal(ind,common2grid);
                gridzlocal_neighbour[2]=0.0;
                gridzlocal_neighbour[3]=0.0;
                
                ind3=-9;
                for ind_tmp in 1:3
                    if cellgridid[cellids[2],ind_tmp]!=cellgridid[ind,1] && cellgridid[cellids[2],ind_tmp]!=cellgridid[ind,2] && cellgridid[cellids[2],ind_tmp]!=cellgridid[ind,3]
                        ind3=cellgridid[cellids[2],ind_tmp];
                    end
                end
                Tmat=[b1[ind,1] b2[ind,1] b3[ind,1]; b1[ind,2] b2[ind,2] b3[ind,2]; b1[ind,3] b2[ind,3] b3[ind,3]];
                xvec=[gridx[ind3]-cellcenterx[ind], gridy[ind3]-cellcentery[ind], gridz[ind3]-cellcenterz[ind]]; #A in global CS
                bvec=Tmat\xvec;
                x=[[bvec[1]], [bvec[2]], [bvec[3]]]; #A in local CS
                Ax=x[1];
                Ay=x[2];
                Az=x[3];
                lambda=dot(x-x0,r0)/dot(r0,r0);
                Q2x=x0[1]+lambda*r0[1];
                Q2y=x0[2]+lambda*r0[2];
                Q2z=x0[3]+lambda*r0[3];
                vec2=[Ax-Q2x, Ay-Q2y, Az-Q2z];
                l2=sqrt(dot(vec2,vec2));
                gridxlocal_neighbour[1]=only(Px+(Q1x-Px)+(Q2x-Q1x)+l2/l1*(Q1x-Px));
                gridylocal_neighbour[1]=only(Py+(Q1y-Py)+(Q2y-Q1y)+l2/l1*(Q1y-Py));
                gridzlocal_neighbour[1]=Float64(0);

                #Construction of LCS f1,f2,f3 according to procedure from above using the points gridxlocal_neighbour(j),gridylocal_neighbour(j)
                ivec1=[only(cellgridid[cellids[2],1]), only(cellgridid[cellids[2],2]), only(cellgridid[cellids[2],3])];                           
                min_val=min(ivec1[1],ivec1[2],ivec1[3]); 
                max_val=max(ivec1[1],ivec1[2],ivec1[3]); 
                idel1=findall(isequal(min(ivec1[1],ivec1[2],ivec1[3])),ivec1);deleteat!(ivec1,idel1);idel1=findall(isequal(max(ivec1[1],ivec1[2])),ivec1);deleteat!(ivec1,idel1);
                median_val=ivec1[1];
                if ind3==min_val; k1=1; elseif ind3==median_val; k2=1; elseif ind3==max_val; k3=1; end                
                ind4=cellgridid[cellids[2],common1grid];
                if ind4==min_val; k1=2; elseif ind4==median_val; k2=2; elseif ind4==max_val; k3=2; end             
                ind5=cellgridid[cellids[2],common2grid];
                if ind5==min_val; k1=3; elseif ind5==median_val; k2=3; elseif ind5==max_val; k3=3; end
        
                f1=[gridxlocal_neighbour[k2]-gridxlocal_neighbour[k1], gridylocal_neighbour[k2]-gridylocal_neighbour[k1], gridzlocal_neighbour[k2]-gridzlocal_neighbour[k1]];
                f1=f1/sqrt(dot(f1,f1));
                a2=[gridxlocal_neighbour[k3]-gridxlocal_neighbour[k1], gridylocal_neighbour[k3]-gridylocal_neighbour[k1], gridzlocal_neighbour[k3]-gridzlocal_neighbour[k1]];
                a2=a2/sqrt(dot(a2,a2));
                f2=a2-dot(f1,a2)/dot(f1,f1)*f1;
                f2=f2/sqrt(dot(f2,f2));
                f3=cross(f1,f2);    
        
                nvec=f3;
                xvec=f1;
                c1=nvec*dot(nvec,xvec)+cos(theta[cellneighboursarray[ind,i_neighbour]])*cross(cross(nvec,xvec),nvec)+sin(theta[cellneighboursarray[ind,i_neighbour]] )*cross(nvec,xvec);
                xvec=f2;
                c2=nvec*dot(nvec,xvec)+cos(theta[cellneighboursarray[ind,i_neighbour]])*cross(cross(nvec,xvec),nvec)+sin(theta[cellneighboursarray[ind,i_neighbour]] )*cross(nvec,xvec);
                xvec=f3;
                c3=nvec*dot(nvec,xvec)+cos(theta[cellneighboursarray[ind,i_neighbour]])*cross(cross(nvec,xvec),nvec)+sin(theta[cellneighboursarray[ind,i_neighbour]] )*cross(nvec,xvec);
                f1=c1;
                f2=c2;
                f3=c3;
                Tmat=[f1[1] f2[1] f3[1]; f1[2] f2[2] f3[2]; f1[3] f2[3] f3[3]];

                #Assign transformation matrix for the velocities in the local coordinate systems
                #(u,v)_e=T*(u,v)_f
                T11[ind,i_neighbour]=Tmat[1,1];
                T12[ind,i_neighbour]=Tmat[1,2];
                T21[ind,i_neighbour]=Tmat[2,1];
                T22[ind,i_neighbour]=Tmat[2,2];
            end

            #calculate cell volume
            vec1=[gridxlocal[ind,2]-gridxlocal[ind,1], gridylocal[ind,2]-gridylocal[ind,1], gridzlocal[ind,2]-gridzlocal[ind,1]];
            vec2=[gridxlocal[ind,3]-gridxlocal[ind,1], gridylocal[ind,3]-gridylocal[ind,1], gridzlocal[ind,3]-gridzlocal[ind,1]];
            vec3=cross(vec1,vec2);
            cellvolume[ind]=cellthickness[ind]*0.5*sqrt(dot(vec3,vec3));
        end  

        return cellvolume, cellcentertocellcenterx, cellcentertocellcentery, T11, T12, T21, T22, cellfacenormalx, cellfacenormaly, cellfacearea
    end


    """
        function plot_mesh(meshfilename,i_mode)

    Create mesh plot with cells with `i_mode==1` and create mesh plots with cell center nodes with `i_mode==2` for manual selection of inlet ports.

    Arguments:
    - meshfilename :: String
    - i_mode :: Int

    Unit test:
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); rtmsim.plot_mesh(meshfilename,1);`

    Additional unit tests:
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); rtmsim.plot_mesh(meshfilename,2);` for the manual selection of inlet ports with left mouse button click while key p is pressed 
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); rtmsim.rtmsim_rev1(1,meshfilename,200, 0.35e5,1.205,1.4,0.06, 0.35e5,0.00e5, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-10,1,1,0,0, 3e-3,0.7,3e-10,1,1,0,0, 0,0,0,0, 0,"results.jld2",1,0.01,16);` for starting only with the interactively selected inlet ports
    """
    function plot_mesh(meshfilename,i_mode)
        if Sys.iswindows()
            meshfilename=replace(meshfilename,"/" => "\\")
        elseif Sys.islinux()
            meshfilename=replace(meshfilename,"\\" => "/")
        end      
        #dummy values for calling function read_mesh
        paramset=[0.5,0.3,3e-10,1.0,1.0,0.0,0.0];paramset1=paramset;paramset2=paramset;paramset3=paramset;paramset4=paramset;
        patchtype1val=-1;patchtype2val=-1;patchtype3val=-1;patchtype4val=-1;i_interactive=0;
        r_p=0.01;
        N,cellgridid,gridx,gridy,gridz,cellcenterx,cellcentery,cellcenterz,patchparameters,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchids1,patchids2,patchids3,patchids4,inletpatchids=
            read_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p);

        #for poly plot
        X=Array{Float64}(undef, 3, N);
        Y=Array{Float64}(undef, 3, N);
        Z=Array{Float64}(undef, 3, N);
        C=Array{Float32}(undef, 3, N);
        for ind in 1:N;
            X[1,ind]=gridx[cellgridid[ind,1]];
            X[2,ind]=gridx[cellgridid[ind,2]];
            X[3,ind]=gridx[cellgridid[ind,3]];
            Y[1,ind]=gridy[cellgridid[ind,1]];
            Y[2,ind]=gridy[cellgridid[ind,2]];
            Y[3,ind]=gridy[cellgridid[ind,3]];
            Z[1,ind]=gridz[cellgridid[ind,1]];
            Z[2,ind]=gridz[cellgridid[ind,2]];
            Z[3,ind]=gridz[cellgridid[ind,3]];
            C[1,ind]=1.0;
            C[2,ind]=1.0;
            C[3,ind]=1.0;
        end
        xyz = reshape([X[:] Y[:] Z[:]]', :)
        #2..for meshscatter plot
        X2=Array{Float64}(undef, 3*N);
        Y2=Array{Float64}(undef, 3*N);
        Z2=Array{Float64}(undef, 3*N);
        C2=Array{Float64}(undef, 3*N);
        for ind in 1:N;
            X2[    ind]=gridx[cellgridid[ind,1]];
            X2[  N+ind]=gridx[cellgridid[ind,2]];
            X2[2*N+ind]=gridx[cellgridid[ind,3]];
            Y2[    ind]=gridy[cellgridid[ind,1]];
            Y2[  N+ind]=gridy[cellgridid[ind,2]];
            Y2[2*N+ind]=gridy[cellgridid[ind,3]];
            Z2[    ind]=gridz[cellgridid[ind,1]];
            Z2[  N+ind]=gridz[cellgridid[ind,2]];
            Z2[2*N+ind]=gridz[cellgridid[ind,3]];
            C2[    ind]=0.0;
            C2[  N+ind]=0.0;
            C2[2*N+ind]=0.0;
        end

        #bounding box
        deltax=maximum(gridx)-minimum(gridx);
        deltay=maximum(gridy)-minimum(gridy);
        deltaz=maximum(gridz)-minimum(gridz);
        mindelta=min(deltax,deltay,deltaz);
        maxdelta=max(deltax,deltay,deltaz);
        if mindelta<maxdelta*0.001;
            eps_delta=maxdelta*0.001;
        else
            eps_delta=0;
        end 
        ax=(deltax+eps_delta)/(mindelta+eps_delta);
        ay=(deltay+eps_delta)/(mindelta+eps_delta);
        az=(deltaz+eps_delta)/(mindelta+eps_delta);
        
        if i_mode==1;
            fig = Figure(resolution=(600, 600))
            ax1 = Axis3(fig[1, 1]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title="Mesh")
            poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C[:], strokewidth=1)
            #hidedecorations!(ax1);
            hidespines!(ax1) 
            display(fig)
        elseif i_mode==2;
            points=rand(Point3f0, length(gridx));
            for i in 1:length(gridx)
                points[i]=Point3f0(gridx[i],gridy[i],gridz[i]);
            end
            positions = Observable(points) 

            inletpos_xyz=[-9.9e9 -9.9e9 -9.9e9];
            filename="inletpostions.jld2"
            @save filename inletpos_xyz

            markersizeval=maxdelta*100;
            fig = Figure()
            ax1 = Axis3(fig[1, 1]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title="Select inlets with p + LMB")
            p=scatter!(ax1, positions,markersize=markersizeval)
            hidedecorations!(ax1);
            hidespines!(ax1) 

            on(events(fig).mousebutton, priority = 2) do event
                if event.button == Mouse.left && event.action == Mouse.press
                    if Keyboard.p in events(fig).keyboardstate
                        plt, i = pick(fig.scene,events(fig).mouseposition[])
                        if plt == p
                            @load filename inletpos_xyz
                            t_div=100;
                            xpos=positions[][i][1];
                            ypos=positions[][i][2];
                            zpos=positions[][i][3];
                            inletpos_xyz=vcat(inletpos_xyz,[xpos ypos zpos]);
                            @save filename inletpos_xyz
                            textpos=string("(" , string(round(t_div*xpos)/t_div) , "," , string(round(t_div*ypos)/t_div) , "," , string(round(t_div*zpos)/t_div) , ")"  )
                            t1=text!(ax1,textpos,position = (xpos,ypos,zpos) ) 
                            scatter!(Point3f0(xpos,ypos,zpos),markersize=2*markersizeval,color = :black)
                            return Consume(true)
                        end
                    end
                end
                return Consume(false)
            end
            display(fig)
        end
    end 


    """
        function plot_sets(meshfilename)
            
    Create a plot with the up to four cell sets defined in the mesh file.

    Unit test:
    - `MODULE_ROOT=splitdir(splitdir(pathof(rtmsim))[1])[1]; meshfilename=joinpath(MODULE_ROOT,"meshfiles","mesh_permeameter1_foursets.bdf"); rtmsim.plot_sets(meshfilename);`
    """
    function plot_sets(meshfilename)
        #dummy values for calling function read_nastran_mesh
        paramset=[0.5,0.3,3e-10,1.0,1.0,0.0,0.0];paramset1=paramset;paramset2=paramset;paramset3=paramset;paramset4=paramset;
        patchtype1val=-1;patchtype2val=-1;patchtype3val=-1;patchtype4val=-1;i_interactive=0;
        r_p=0.01;
        N,cellgridid,gridx,gridy,gridz,cellcenterx,cellcentery,cellcenterz,patchparameters,patchparameters1,patchparameters2,patchparameters3,patchparameters4,patchids1,patchids2,patchids3,patchids4,inletpatchids=
            read_mesh(meshfilename,paramset,paramset1,paramset2,paramset3,paramset4,patchtype1val,patchtype2val,patchtype3val,patchtype4val,i_interactive,r_p);

        if isempty(patchids1);
            n_patch=0;
            errorstring=string("No sets defined"* "\n"); 
            error(errorstring);
        else
            if isempty(patchids2);
                n_patch=1;
            else
                if isempty(patchids3);
                    n_patch=2;
                else
                    if isempty(patchids4);
                        n_patch=3;
                    else
                        n_patch=4;
                    end
                end
            end
        end
      
        #for poly plot
        X=Array{Float64}(undef, 3, N);
        Y=Array{Float64}(undef, 3, N);
        Z=Array{Float64}(undef, 3, N);
        C=Array{Float32}(undef, 3, N);
        C_patch1=Array{Float32}(undef, 3, N);
        C_patch2=Array{Float32}(undef, 3, N);
        C_patch3=Array{Float32}(undef, 3, N);
        C_patch4=Array{Float32}(undef, 3, N);
        for ind in 1:N;
            X[1,ind]=gridx[cellgridid[ind,1]];
            X[2,ind]=gridx[cellgridid[ind,2]];
            X[3,ind]=gridx[cellgridid[ind,3]];
            Y[1,ind]=gridy[cellgridid[ind,1]];
            Y[2,ind]=gridy[cellgridid[ind,2]];
            Y[3,ind]=gridy[cellgridid[ind,3]];
            Z[1,ind]=gridz[cellgridid[ind,1]];
            Z[2,ind]=gridz[cellgridid[ind,2]];
            Z[3,ind]=gridz[cellgridid[ind,3]];
            C[1,ind]=1.0;
            C[2,ind]=1.0;
            C[3,ind]=1.0;
            if issubset(ind, patchids1)
                C_patch1[1,ind]=1.0;
                C_patch1[2,ind]=1.0;
                C_patch1[3,ind]=1.0;
            else
                C_patch1[1,ind]=0.0;
                C_patch1[2,ind]=0.0;
                C_patch1[3,ind]=0.0;
            end   
            if issubset(ind, patchids2)
                C_patch2[1,ind]=1.0;
                C_patch2[2,ind]=1.0;
                C_patch2[3,ind]=1.0;
            else
                C_patch2[1,ind]=0.0;
                C_patch2[2,ind]=0.0;
                C_patch2[3,ind]=0.0;
            end         
            if issubset(ind, patchids3)
                C_patch3[1,ind]=1.0;
                C_patch3[2,ind]=1.0;
                C_patch3[3,ind]=1.0;
            else
                C_patch3[1,ind]=0.0;
                C_patch3[2,ind]=0.0;
                C_patch3[3,ind]=0.0;
            end  
            if issubset(ind, patchids4)
                C_patch4[1,ind]=1.0;
                C_patch4[2,ind]=1.0;
                C_patch4[3,ind]=1.0;
            else
                C_patch4[1,ind]=0.0;
                C_patch4[2,ind]=0.0;
                C_patch4[3,ind]=0.0;
            end        
        end
        xyz = reshape([X[:] Y[:] Z[:]]', :)

        #2..for meshscatter plot
        X2=Array{Float64}(undef, 3*N);
        Y2=Array{Float64}(undef, 3*N);
        Z2=Array{Float64}(undef, 3*N);
        C2=Array{Float64}(undef, 3*N);
        for ind in 1:N;
            X2[    ind]=gridx[cellgridid[ind,1]];
            X2[  N+ind]=gridx[cellgridid[ind,2]];
            X2[2*N+ind]=gridx[cellgridid[ind,3]];
            Y2[    ind]=gridy[cellgridid[ind,1]];
            Y2[  N+ind]=gridy[cellgridid[ind,2]];
            Y2[2*N+ind]=gridy[cellgridid[ind,3]];
            Z2[    ind]=gridz[cellgridid[ind,1]];
            Z2[  N+ind]=gridz[cellgridid[ind,2]];
            Z2[2*N+ind]=gridz[cellgridid[ind,3]];
            C2[    ind]=0.0;
            C2[  N+ind]=0.0;
            C2[2*N+ind]=0.0;
        end

        resolution_val=300;
        if n_patch==1;
            fig = Figure(resolution=(1*resolution_val, resolution_val))
        elseif n_patch==2;
            fig = Figure(resolution=(2*resolution_val, 2*resolution_val))
        elseif n_patch==3;
            fig = Figure(resolution=(3*resolution_val, resolution_val))
        elseif n_patch==4;
            fig = Figure(resolution=(4*resolution_val, resolution_val))
        end

        #bounding box
        deltax=maximum(gridx)-minimum(gridx);
        deltay=maximum(gridy)-minimum(gridy);
        deltaz=maximum(gridz)-minimum(gridz);
        mindelta=min(deltax,deltay,deltaz);
        maxdelta=max(deltax,deltay,deltaz); 
        if mindelta<maxdelta*0.001;
            eps_delta=maxdelta*0.001;
        else
            eps_delta=0;
        end 
        ax=(deltax+eps_delta)/(mindelta+eps_delta);
        ay=(deltay+eps_delta)/(mindelta+eps_delta);
        az=(deltaz+eps_delta)/(mindelta+eps_delta);
        ax1 = Axis3(fig[1, 1]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title="Set 1")
        poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_patch1[:], strokewidth=1)
        hidedecorations!(ax1);hidespines!(ax1) 
        if n_patch>=2;
            ax2 = Axis3(fig[1, 2]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title="Set 2")
            poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_patch2[:], strokewidth=1)
            hidedecorations!(ax2);hidespines!(ax2) 
        end
        if n_patch>=3;
            ax3 = Axis3(fig[1, 3]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title="Set 3")
            poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_patch3[:], strokewidth=1)
            hidedecorations!(ax3);hidespines!(ax3) 
        end
        if n_patch>=4;
            ax4 = Axis3(fig[1, 4]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title="Set 4")
            poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_patch4[:], strokewidth=1)
            hidedecorations!(ax4);hidespines!(ax4) 
        end
        display(fig)
    end

    """
        function assign_pset(r_p,N,cellcenterx,cellcentery,cellcenterz)

    Create the cell set from the manually selected inlet port nodes
    """
    function assign_pset(r_p,N,cellcenterx,cellcentery,cellcenterz)
        filename="inletpostions.jld2"
        @load filename inletpos_xyz
        n_p=size(inletpos_xyz,1)-1;
        patchpids=[];
        i=1;
        for i_p in 2:n_p+1;
            r_p_temp=r_p;
            i_add=1;
            for ind in 1:N
                vec1=[cellcenterx[ind]-inletpos_xyz[i_p,1],cellcentery[ind]-inletpos_xyz[i_p,2],cellcenterz[ind]-inletpos_xyz[i_p,3]]
                if sqrt(dot(vec1,vec1))<=r_p_temp;
                   patchpids=vcat(patchpids,ind);
                   i=i+1;
                   i_add=0;
                end
            end
            while i_add==1;
                r_p_temp=1.1*r_p_temp;
                i_firstcell=0;
                for ind in 1:N
                    vec1=[cellcenterx[ind]-inletpos_xyz[i_p,1],cellcentery[ind]-inletpos_xyz[i_p,2],cellcenterz[ind]-inletpos_xyz[i_p,3]]
                    if sqrt(dot(vec1,vec1))<=r_p_temp  && i_firstcell==0;
                        patchpids=vcat(patchpids,ind);
                        i_firstcell=1;
                        i=i+1;
                        i_add=0;
                    end
                end
            end
        end
        pset=patchpids;
        psetfilename="pset.jld2"
        @save psetfilename pset;
    end

    """
        function plot_results(resultsfilename)

    Create contour plots of the filling factor and the pressure after loading a results file.

    Arguments:
    - resultsfilename :: String
    
    Unit test: 
    - `WORK_DIR=pwd(); resultsfilename=joinpath(WORK_DIR,"results.jld2"); rtmsim.plot_results(resultsfilename);`
    """
    function plot_results(resultsfilename)
        #create contour plots of the filling factor and the pressure after loading a results file
        #default call: rtmsim.plot_results("results.jld2")

        if ~isfile(resultsfilename);
            errorstring=string("File ",resultsfilename," not existing"* "\n"); 
            error(errorstring);
        end
        t_digits=2; 
        t_div=10^2;
        @load resultsfilename t rho_new u_new v_new p_new gamma_new gamma_out gridx gridy gridz cellgridid N n_out

        gamma_plot=Vector{Float64}(undef, N);
        deltap=maximum(p_new)-minimum(p_new);     
        for ind=1:N;
            if gamma_out[ind]>0.8;
                gamma_plot[ind]=1;
            else
                gamma_plot[ind]=0;
            end
        end
        deltagamma=1;  #deltagamma=maximum(gamma_plot)-minimum(gamma_plot);

        #for poly plot
        inds0=findall(gamma_out.>-0.5);
        N0=length(inds0);
        X=Array{Float64}(undef, 3, N0);
        Y=Array{Float64}(undef, 3, N0);
        Z=Array{Float64}(undef, 3, N0);
        C_p=Array{Float32}(undef, 3, N0);        
        C_gamma=Array{Float32}(undef, 3, N0);
        inds1=findall(gamma_out.<-0.5);
        N1=length(inds1);
        X1=Array{Float64}(undef, 3, N1);
        Y1=Array{Float64}(undef, 3, N1);
        Z1=Array{Float64}(undef, 3, N1);  
        C1_gamma=Array{Float32}(undef, 3, N1);
        C1_p=Array{Float32}(undef, 3, N1);
        for i in 1:N0;
            ind=inds0[i];
            X[1,i]=gridx[cellgridid[ind,1]];
            X[2,i]=gridx[cellgridid[ind,2]];
            X[3,i]=gridx[cellgridid[ind,3]];
            Y[1,i]=gridy[cellgridid[ind,1]];
            Y[2,i]=gridy[cellgridid[ind,2]];
            Y[3,i]=gridy[cellgridid[ind,3]];
            Z[1,i]=gridz[cellgridid[ind,1]];
            Z[2,i]=gridz[cellgridid[ind,2]];
            Z[3,i]=gridz[cellgridid[ind,3]];
            C_gamma[1,i]=gamma_plot[ind]/deltagamma;
            C_gamma[2,i]=gamma_plot[ind]/deltagamma;
            C_gamma[3,i]=gamma_plot[ind]/deltagamma;
            C_p[1,i]=p_new[ind]/deltap;
            C_p[2,i]=p_new[ind]/deltap;
            C_p[3,i]=p_new[ind]/deltap;
        end
        xyz = reshape([X[:] Y[:] Z[:]]', :)        
        for i in 1:N1
            ind=inds1[i];
            X1[1,i]=gridx[cellgridid[ind,1]];
            X1[2,i]=gridx[cellgridid[ind,2]];
            X1[3,i]=gridx[cellgridid[ind,3]];
            Y1[1,i]=gridy[cellgridid[ind,1]];
            Y1[2,i]=gridy[cellgridid[ind,2]];
            Y1[3,i]=gridy[cellgridid[ind,3]];
            Z1[1,i]=gridz[cellgridid[ind,1]];
            Z1[2,i]=gridz[cellgridid[ind,2]];
            Z1[3,i]=gridz[cellgridid[ind,3]];
            C1_gamma[1,i]=0.5;
            C1_gamma[2,i]=0.5;
            C1_gamma[3,i]=0.5;
            C1_p[1,i]=p_new[ind]/deltap;
            C1_p[2,i]=p_new[ind]/deltap;
            C1_p[3,i]=p_new[ind]/deltap;
        end
        xyz1 = reshape([X1[:] Y1[:] Z1[:]]', :)

        #bounding box
        deltax=maximum(gridx)-minimum(gridx);
        deltay=maximum(gridy)-minimum(gridy);
        deltaz=maximum(gridz)-minimum(gridz);
        mindelta=min(deltax,deltay,deltaz);
        maxdelta=max(deltax,deltay,deltaz);
        if mindelta<maxdelta*0.001;
            eps_delta=maxdelta*0.001;
        else
            eps_delta=0;
        end 
        ax=(deltax+eps_delta)/(mindelta+eps_delta);
        ay=(deltay+eps_delta)/(mindelta+eps_delta);
        az=(deltaz+eps_delta)/(mindelta+eps_delta);

        resolution_val=600;
        fig = Figure(resolution=(2*resolution_val, resolution_val))
        ax1 = Axis3(fig[1, 1]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title=string("Filling factor at t=", string(round(t_div*t)/t_div) ,"s"))
        poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_gamma[:], strokewidth=1, colorrange=(0,1))
        if N1>0; 
            poly!(connect(xyz1, Makie.Point{3}), connect(1:length(X1), TriangleFace); color=C1_gamma[:], strokewidth=1, colorrange=(0,1),colormap = (:bone))
        end
        hidedecorations!(ax1);
        hidespines!(ax1) 
        ax2 = Axis3(fig[1, 2]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title=string("Pressure at t=", string(round(t_div*t)/t_div) ,"s"))
        poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_p[:], strokewidth=1, colorrange=(0,1))
        if N1>0; 
            poly!(connect(xyz1, Makie.Point{3}), connect(1:length(X1), TriangleFace); color=C1_p[:], strokewidth=1, colorrange=(0,1))
        end
        Colorbar(fig[1, 3], limits = (0, deltap), colormap = :viridis,  vertical=true, height=Relative(0.5));  
        #Colorbar(fig[2, 2], limits = (0, deltap), colormap = :viridis,  vertical=false, width=Relative(0.5));
        hidedecorations!(ax2);
        hidespines!(ax2) 
        display(fig)
    end 


    """
        function plot_overview(n_out,n_pics)

    Create filling factor contour plots. `n_out` is the index of the last output file, if `n_out==-1` the output file with the highest index is chosen. Consider the last `n_pics` for creating the contour plots at four equidistant time intervals, if `n_pics==-1` all available output files are considered.

    Arguments:
    - n_out :: Int
    - n_pics :: Int

    Unit test: 
    - `rtmsim.plot_overview(-1,-1)`
    """
    function plot_overview(n_out,n_pics)
        #

        val=0;
		n_out_start=-1;
        if n_out==-1;
            vec1=glob("output_*.jld2");
            for i=1:length(vec1);
                vec2=split(vec1[i],".")
                vec3=split(vec2[1],"_")
                val=max(val,parse(Int64,vec3[2]))
				if i==1;
				    n_out_start=parse(Int64,vec3[2]);
				end
            end            
            n_out=val;
        end
		if n_pics==-1;
		    n_pics=(n_out-n_out_start);
		end
        if mod(n_pics,4)!=0;
            errorstring=string("n_pics must be multiple of four"* "\n"); 
            error(errorstring);
        end
        t_digits=2; 
        t_div=10^2;

        resolution_val=300;
        fig = Figure(resolution=(4*resolution_val, resolution_val))
        i_out=n_out-3*Int64(n_pics/4);
        for i_plot in 1:4;          
            outputfilename=string("output_",string(i_out),".jld2");
            if ~isfile(outputfilename);
                errorstring=string("File ",outputfilename," not existing"* "\n"); 
                error(errorstring);
            else
                loadfilename="results_temp.jld2"
                cp(outputfilename,loadfilename;force=true);
                @load loadfilename t rho_new u_new v_new p_new gamma_new gamma_out gridx gridy gridz cellgridid N n_out
            end

            gamma_plot=Vector{Float64}(undef, N);
            deltap=maximum(p_new)-minimum(p_new);      
            for ind=1:N;
                if gamma_out[ind]>0.8;
                    gamma_plot[ind]=1;
                else
                    gamma_plot[ind]=0;
                end
            end
            deltagamma=1;  #deltagamma=maximum(gamma_plot)-minimum(gamma_plot);

            #for poly plot
            inds0=findall(gamma_out.>-0.5);
            N0=length(inds0);
            X=Array{Float64}(undef, 3, N0);
            Y=Array{Float64}(undef, 3, N0);
            Z=Array{Float64}(undef, 3, N0);
            C_p=Array{Float32}(undef, 3, N0);        
            C_gamma=Array{Float32}(undef, 3, N0);
            inds1=findall(gamma_out.<-0.5);
            N1=length(inds1);
            X1=Array{Float64}(undef, 3, N1);
            Y1=Array{Float64}(undef, 3, N1);
            Z1=Array{Float64}(undef, 3, N1);  
            C1_p=Array{Float32}(undef, 3, N1);
            C1_gamma=Array{Float32}(undef, 3, N1);
            for i in 1:N0;
                ind=inds0[i];
                X[1,i]=gridx[cellgridid[ind,1]];
                X[2,i]=gridx[cellgridid[ind,2]];
                X[3,i]=gridx[cellgridid[ind,3]];
                Y[1,i]=gridy[cellgridid[ind,1]];
                Y[2,i]=gridy[cellgridid[ind,2]];
                Y[3,i]=gridy[cellgridid[ind,3]];
                Z[1,i]=gridz[cellgridid[ind,1]];
                Z[2,i]=gridz[cellgridid[ind,2]];
                Z[3,i]=gridz[cellgridid[ind,3]];
                C_gamma[1,i]=gamma_plot[ind]/deltagamma;
                C_gamma[2,i]=gamma_plot[ind]/deltagamma;
                C_gamma[3,i]=gamma_plot[ind]/deltagamma;
                C_p[1,i]=p_new[ind]/deltap;
                C_p[2,i]=p_new[ind]/deltap;
                C_p[3,i]=p_new[ind]/deltap;
            end
            xyz = reshape([X[:] Y[:] Z[:]]', :)
            for i in 1:N1
                ind=inds1[i];
                X1[1,i]=gridx[cellgridid[ind,1]];
                X1[2,i]=gridx[cellgridid[ind,2]];
                X1[3,i]=gridx[cellgridid[ind,3]];
                Y1[1,i]=gridy[cellgridid[ind,1]];
                Y1[2,i]=gridy[cellgridid[ind,2]];
                Y1[3,i]=gridy[cellgridid[ind,3]];
                Z1[1,i]=gridz[cellgridid[ind,1]];
                Z1[2,i]=gridz[cellgridid[ind,2]];
                Z1[3,i]=gridz[cellgridid[ind,3]];
                C1_gamma[1,i]=0.5;
                C1_gamma[2,i]=0.5;
                C1_gamma[3,i]=0.5;
                C1_p[1,i]=p_new[ind]/deltap;
                C1_p[2,i]=p_new[ind]/deltap;
                C1_p[3,i]=p_new[ind]/deltap;
            end
            xyz1 = reshape([X1[:] Y1[:] Z1[:]]', :)

            #bounding box
            deltax=maximum(gridx)-minimum(gridx);
            deltay=maximum(gridy)-minimum(gridy);
            deltaz=maximum(gridz)-minimum(gridz);
            mindelta=min(deltax,deltay,deltaz);
            maxdelta=max(deltax,deltay,deltaz);
            if mindelta<maxdelta*0.001;
                eps_delta=maxdelta*0.001;
            else
                eps_delta=0;
            end 
            ax=(deltax+eps_delta)/(mindelta+eps_delta);
            ay=(deltay+eps_delta)/(mindelta+eps_delta);
            az=(deltaz+eps_delta)/(mindelta+eps_delta);
            if i_plot==1;
                ax1 = Axis3(fig[1, 1]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title=string("Filling factor at t=", string(round(t_div*t)/t_div) ,"s"))
                poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_gamma[:], strokewidth=1, colorrange=(0,1))
                if N1>0;
                    poly!(connect(xyz1, Makie.Point{3}), connect(1:length(X1), TriangleFace); color=C1_gamma[:], strokewidth=1, colorrange=(0,1),colormap = (:bone))
                end
                hidedecorations!(ax1);
                hidespines!(ax1) 
            elseif i_plot==2
                ax2 = Axis3(fig[1, 2]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title=string("Filling factor at t=", string(round(t_div*t)/t_div) ,"s"))
                poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_gamma[:], strokewidth=1, colorrange=(0,1))
                if N1>0;
                    poly!(connect(xyz1, Makie.Point{3}), connect(1:length(X1), TriangleFace); color=C1_gamma[:], strokewidth=1, colorrange=(0,1),colormap = (:bone))
                end
                hidedecorations!(ax2);
                hidespines!(ax2) 
            elseif i_plot==3
                ax3 = Axis3(fig[1, 3]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title=string("Filling factor at t=", string(round(t_div*t)/t_div) ,"s"))
                poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_gamma[:], strokewidth=1, colorrange=(0,1))
                if N1>0;
                    poly!(connect(xyz1, Makie.Point{3}), connect(1:length(X1), TriangleFace); color=C1_gamma[:], strokewidth=1, colorrange=(0,1),colormap = (:bone))
                end
                hidedecorations!(ax3);
                hidespines!(ax3) 
            elseif i_plot==4
                ax4 = Axis3(fig[1, 4]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title=string("Filling factor at t=", string(round(t_div*t)/t_div) ,"s"))
                poly!(connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_gamma[:], strokewidth=1, colorrange=(0,1))
                if N1>0;
                    poly!(connect(xyz1, Makie.Point{3}), connect(1:length(X1), TriangleFace); color=C1_gamma[:], strokewidth=1, colorrange=(0,1),colormap = (:bone))
                end
                hidedecorations!(ax4);
                hidespines!(ax4) 
            end
            i_out=i_out+Int64(n_pics/4);
        end
        display(fig)
    end 


    """
        function plot_filling(n_out,n_pics)

    Create a window showing the filling factor contour plot at a selected time instance. Selection is with slider bar. `n_out` is the index of the last output file, if `n_out==-1` the output file with the highest index is chosen. Consider the last `n_pics` for creating the contour plots at four equidistant time intervals, if `n_pics==-1` all available output files are considered.
    
    Arguments: 
    - n_out :: Int
    - n_pics :: Int

    Unit test:
    - `rtmsim.plot_filling(-1,-1)` 
    """
    function plot_filling(n_out,n_pics)
        val=0;
		n_out_start=-1;
        if n_out==-1;
            vec1=glob("output_*.jld2");
            for i=1:length(vec1);
                vec2=split(vec1[i],".")
                vec3=split(vec2[1],"_")
                val=max(val,parse(Int64,vec3[2]))
				if i==1;
				    n_out_start=parse(Int64,vec3[2]);
				end
            end            
            n_out=val;
        end
		if n_pics==-1;
		    n_pics=(n_out-n_out_start);
		end
        #plot the last n_pics pictures
        if n_pics<4;
            errorstring=string("Makes no sense for n_pics<4"* "\n"); 
            error(errorstring);
        end
        t_digits=2; 
        t_div=10^2;
        
        time_vector=[];
        output_array=[];
        inds=[];
        inds0=[];
        inds1=[];
        N=Int64(0);
        N0=Int64(0);
        N1=Int64(0);
        ax=Float64(0.0);
        ay=Float64(0.0);
        az=Float64(0.0);
        t=Float64(0);
        xyz=Vector{Float64};
        xyz1=Vector{Float64};
        X=Vector{Float64};
        Y=Vector{Float64};
        Z=Vector{Float64};
        C=Vector{Float64};
        X1=Vector{Float64};
        Y1=Vector{Float64};
        Z1=Vector{Float64};
        C1_gamma=Vector{Float64};        
        i_out=n_out-n_pics;
        i_firstfile=1;
        for i_plot in 1:n_pics+1;          
            outputfilename=string("output_",string(i_out),".jld2");
            if ~isfile(outputfilename);
                errorstring=string("File ",outputfilename," not existing"* "\n"); 
                error(errorstring);
            else
                loadfilename="results_temp.jld2"
                cp(outputfilename,loadfilename;force=true);
                @load loadfilename t rho_new u_new v_new p_new gamma_new gamma_out gridx gridy gridz cellgridid N n_out
                #print(string(i_plot)*" \n")
                #print(string(i_out)*" \n")
                if i_firstfile==1;
                    i_firstfile=0;
                    #for poly plot
                    inds0=findall(gamma_out.>-0.5);
                    N0=length(inds0);
                    X=Array{Float64}(undef, 3, N0);
                    Y=Array{Float64}(undef, 3, N0);
                    Z=Array{Float64}(undef, 3, N0);
                    C_p=Array{Float32}(undef, 3, N0);        
                    C_gamma=Array{Float32}(undef, 3, N0);
                    inds1=findall(gamma_out.<-0.5);
                    N1=length(inds1);
                    X1=Array{Float64}(undef, 3, N1);
                    Y1=Array{Float64}(undef, 3, N1);
                    Z1=Array{Float64}(undef, 3, N1);  
                    C1_gamma=Array{Float32}(undef, 3, N1);
                    for i in 1:N0;
                        ind=inds0[i];
                        X[1,i]=gridx[cellgridid[ind,1]];
                        X[2,i]=gridx[cellgridid[ind,2]];
                        X[3,i]=gridx[cellgridid[ind,3]];
                        Y[1,i]=gridy[cellgridid[ind,1]];
                        Y[2,i]=gridy[cellgridid[ind,2]];
                        Y[3,i]=gridy[cellgridid[ind,3]];
                        Z[1,i]=gridz[cellgridid[ind,1]];
                        Z[2,i]=gridz[cellgridid[ind,2]];
                        Z[3,i]=gridz[cellgridid[ind,3]];
                    end
                    xyz = reshape([X[:] Y[:] Z[:]]', :)
                    for i in 1:N1
                        ind=inds1[i];
                        X1[1,i]=gridx[cellgridid[ind,1]];
                        X1[2,i]=gridx[cellgridid[ind,2]];
                        X1[3,i]=gridx[cellgridid[ind,3]];
                        Y1[1,i]=gridy[cellgridid[ind,1]];
                        Y1[2,i]=gridy[cellgridid[ind,2]];
                        Y1[3,i]=gridy[cellgridid[ind,3]];
                        Z1[1,i]=gridz[cellgridid[ind,1]];
                        Z1[2,i]=gridz[cellgridid[ind,2]];
                        Z1[3,i]=gridz[cellgridid[ind,3]];
                        C1_gamma[1,i]=0.5;
                        C1_gamma[2,i]=0.5;
                        C1_gamma[3,i]=0.5;
                    end
                    xyz1 = reshape([X1[:] Y1[:] Z1[:]]', :)

                    #bounding box
                    deltax=maximum(gridx)-minimum(gridx);
                    deltay=maximum(gridy)-minimum(gridy);
                    deltaz=maximum(gridz)-minimum(gridz);
                    mindelta=min(deltax,deltay,deltaz);
                    maxdelta=max(deltax,deltay,deltaz);
                    if mindelta<maxdelta*0.001;
                        eps_delta=maxdelta*0.001;
                    else
                        eps_delta=0;
                    end 
                    ax=(deltax+eps_delta)/(mindelta+eps_delta);
                    ay=(deltay+eps_delta)/(mindelta+eps_delta);
                    az=(deltaz+eps_delta)/(mindelta+eps_delta);
                    time_vector=t;
                    output_array=gamma_out; 
                    N_val=N;

                else
                    time_vector=vcat(time_vector,t);
                    output_array=hcat(output_array,gamma_out);
                end
            end
            i_out=i_out+1;
        end

        gamma_plot=output_array[:,end]  
        for ind=1:N;
            if gamma_plot[ind]>0.8;
                gamma_plot[ind]=1;
            else
                gamma_plot[ind]=0;
            end
        end
        deltagamma=1;  #deltagamma=maximum(gamma_plot)-minimum(gamma_plot);
        
        C_gamma=Array{Float32}(undef, 3, N0);
        for i in 1:N0;
            ind=inds0[i];
            C_gamma[1,i]=gamma_plot[ind]/deltagamma;
            C_gamma[2,i]=gamma_plot[ind]/deltagamma;
            C_gamma[3,i]=gamma_plot[ind]/deltagamma;
        end

        resolution_val=600;
        fig = Figure(resolution=(resolution_val, resolution_val))   
        ax1 = Axis3(fig[1, 1]; aspect=(ax,ay,az), perspectiveness=0.5,viewmode = :fitzoom,title=string("Filling factor at t=", string(round(t_div*t)/t_div) ,"s"))
        #p1=poly!(ax1,connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_gamma[:], strokewidth=1, colorrange=(0,1))
        #if N1>0;
        #    p2=poly!(ax1,connect(xyz1, Makie.Point{3}), connect(1:length(X1), TriangleFace); color=C1_gamma[:], strokewidth=1, colorrange=(0,1),colormap = (:bone))
        #end
        hidedecorations!(ax1);
        hidespines!(ax1) 
        #display(fig)
        #sl_t = Slider(fig[2, 1], range = time_vector[1]:  (time_vector[end]-time_vector[1])/n_pics :time_vector[end], startvalue =  time_vector[end] );
        sl_t = Slider(fig[2, 1], range = time_vector[1]:  (time_vector[end]-time_vector[1])/n_pics :time_vector[end], startvalue =  time_vector[1] );
        point = lift(sl_t.value) do x           
            if x<0.5*(time_vector[end]+time_vector[1]);
                gamma_plot=output_array[:,1]
            else
                gamma_plot=output_array[:,end]
            end
            time_val=x
            tind=1
            tind1=1
            tind2=2
            for i in 1:length(time_vector)-1;
                if x>=0.5*(time_vector[i]+time_vector[i+1])
                    tind=i+1;
                end
            end            
            gamma_plot=output_array[:,tind]
            time_val=time_vector[tind]

            for ind=1:N;
                if gamma_plot[ind]>0.8;
                    gamma_plot[ind]=1;
                else
                    gamma_plot[ind]=0;
                end
            end
            deltagamma=1;  #maximum(gamma_plot)-minimum(gamma_plot);
            for i in 1:N0;
                ind=inds0[i];
                C_gamma[1,i]=gamma_plot[ind]/deltagamma;
                C_gamma[2,i]=gamma_plot[ind]/deltagamma;
                C_gamma[3,i]=gamma_plot[ind]/deltagamma;
            end
            empty!(ax1.scene)
            p1=poly!(ax1,connect(xyz, Makie.Point{3}), connect(1:length(X), TriangleFace); color=C_gamma[:], strokewidth=1, colorrange=(0,1))
            if N1>0;
                p2=poly!(ax1,connect(xyz1, Makie.Point{3}), connect(1:length(X1), TriangleFace); color=C1_gamma[:], strokewidth=1, colorrange=(0,1),colormap = (:bone))
            end
            ax1.title=string("Filling factor at t=", string(round(t_div*time_val)/t_div) ,"s")
            hidedecorations!(ax1);
            hidespines!(ax1) 
            display(fig)
        end
    end 

    """
        function gui()
    
    Opens the GUI.
    """
    function gui()
        #one Gtk window
        win = GtkWindow("RTMsim"); 

        #define buttons
        sm=GtkButton("Select mesh file");pm=GtkButton("Plot mesh");ps=GtkButton("Plot sets")
        ss=GtkButton("Start simulation");cs=GtkButton("Continue simulation")
        sel=GtkButton("Select inlet port"); si=GtkButton("Start interactive");ci=GtkButton("Continue interactive");
        sr=GtkButton("Select results file");pr=GtkButton("Plot results")
        po=GtkButton("Plot overview")
        pf=GtkButton("Plot filling")
        q=GtkButton("Quit")
        h=GtkButton("Help")
        in1=GtkButton("Select input file")
        in3=GtkButton("Run with input file")

        #define input fields
        #in2=GtkEntry(); set_gtk_property!(in2,:text,"inputfiles\\input.txt");
        #mf=GtkEntry(); set_gtk_property!(mf,:text,"meshfiles\\mesh_permeameter1_foursets.bdf");
        in2=GtkEntry(); set_gtk_property!(in2,:text,"");
        mf=GtkEntry(); set_gtk_property!(mf,:text,"");
        t=GtkEntry(); set_gtk_property!(t,:text,"200")
        rf=GtkEntry(); set_gtk_property!(rf,:text,"results.jld2")
        r=GtkEntry(); set_gtk_property!(r,:text,"0.01")
        p1_0=GtkEntry(); set_gtk_property!(p1_0,:text,"Set 1");GAccessor.editable(GtkEditable(p1_0),false) 
        p2_0=GtkEntry(); set_gtk_property!(p2_0,:text,"Set 2");GAccessor.editable(GtkEditable(p2_0),false) 
        p3_0=GtkEntry(); set_gtk_property!(p3_0,:text,"Set 3");GAccessor.editable(GtkEditable(p3_0),false) 
        p4_0=GtkEntry(); set_gtk_property!(p4_0,:text,"Set 4");GAccessor.editable(GtkEditable(p4_0),false) 
        par_1=GtkEntry(); set_gtk_property!(par_1,:text,"135000")
        par_2=GtkEntry(); set_gtk_property!(par_2,:text,"100000")
        par_3=GtkEntry(); set_gtk_property!(par_3,:text,"0.06")
        p0_1=GtkEntry(); set_gtk_property!(p0_1,:text,"0.003")
        p0_2=GtkEntry(); set_gtk_property!(p0_2,:text,"0.7")
        p0_3=GtkEntry(); set_gtk_property!(p0_3,:text,"3e-10")
        p0_4=GtkEntry(); set_gtk_property!(p0_4,:text,"1")
        p0_5=GtkEntry(); set_gtk_property!(p0_5,:text,"1")
        p0_6=GtkEntry(); set_gtk_property!(p0_6,:text,"0")
        p0_7=GtkEntry(); set_gtk_property!(p0_7,:text,"0")
        p1_1=GtkEntry(); set_gtk_property!(p1_1,:text,"0.003")
        p1_2=GtkEntry(); set_gtk_property!(p1_2,:text,"0.7")
        p1_3=GtkEntry(); set_gtk_property!(p1_3,:text,"3e-10")
        p1_4=GtkEntry(); set_gtk_property!(p1_4,:text,"1")
        p1_5=GtkEntry(); set_gtk_property!(p1_5,:text,"1")
        p1_6=GtkEntry(); set_gtk_property!(p1_6,:text,"0")
        p1_7=GtkEntry(); set_gtk_property!(p1_7,:text,"0")
        p2_1=GtkEntry(); set_gtk_property!(p2_1,:text,"0.003")
        p2_2=GtkEntry(); set_gtk_property!(p2_2,:text,"0.7")
        p2_3=GtkEntry(); set_gtk_property!(p2_3,:text,"3e-10")
        p2_4=GtkEntry(); set_gtk_property!(p2_4,:text,"1")
        p2_5=GtkEntry(); set_gtk_property!(p2_5,:text,"1")
        p2_6=GtkEntry(); set_gtk_property!(p2_6,:text,"0")
        p2_7=GtkEntry(); set_gtk_property!(p2_7,:text,"0")
        p3_1=GtkEntry(); set_gtk_property!(p3_1,:text,"0.003")
        p3_2=GtkEntry(); set_gtk_property!(p3_2,:text,"0.7")
        p3_3=GtkEntry(); set_gtk_property!(p3_3,:text,"3e-10")
        p3_4=GtkEntry(); set_gtk_property!(p3_4,:text,"1")
        p3_5=GtkEntry(); set_gtk_property!(p3_5,:text,"1")
        p3_6=GtkEntry(); set_gtk_property!(p3_6,:text,"0")
        p3_7=GtkEntry(); set_gtk_property!(p3_7,:text,"0")
        p4_1=GtkEntry(); set_gtk_property!(p4_1,:text,"0.003")
        p4_2=GtkEntry(); set_gtk_property!(p4_2,:text,"0.7")
        p4_3=GtkEntry(); set_gtk_property!(p4_3,:text,"3e-10")
        p4_4=GtkEntry(); set_gtk_property!(p4_4,:text,"1")
        p4_5=GtkEntry(); set_gtk_property!(p4_5,:text,"1")
        p4_6=GtkEntry(); set_gtk_property!(p4_6,:text,"0")
        p4_7=GtkEntry(); set_gtk_property!(p4_7,:text,"0")

        #define radio buttons
        choices = ["Ignore",  "Pressure inlet", "Pressure outlet", "Patch" ]
        f1 = Gtk.GtkBox(:v);
        r1 = Vector{RadioButton}(undef, 4)
        r1[1] = RadioButton(choices[1]);                   push!(f1,r1[1])
        r1[2] = RadioButton(r1[1],choices[2],active=true); push!(f1,r1[2])
        r1[3] = RadioButton(r1[2],choices[3]);             push!(f1,r1[3])
        r1[4] = RadioButton(r1[3],choices[4]);             push!(f1,r1[4])
        f2 = Gtk.GtkBox(:v);
        r2 = Vector{RadioButton}(undef, 4)
        r2[1] = RadioButton(choices[1],active=true); push!(f2,r2[1])
        r2[2] = RadioButton(r2[1],choices[2]);       push!(f2,r2[2])
        r2[3] = RadioButton(r2[2],choices[3]);       push!(f2,r2[3])
        r2[4] = RadioButton(r2[3],choices[4]);       push!(f2,r2[4])
        f3 = Gtk.GtkBox(:v);
        r3 = Vector{RadioButton}(undef, 4)
        r3[1] = RadioButton(choices[1],active=true); push!(f3,r3[1])
        r3[2] = RadioButton(r3[1],choices[2]);       push!(f3,r3[2])
        r3[3] = RadioButton(r3[2],choices[3]);       push!(f3,r3[3])
        r3[4] = RadioButton(r3[3],choices[4]);       push!(f3,r3[4])
        f4 = Gtk.GtkBox(:v);
        r4 = Vector{RadioButton}(undef, 4)
        r4[1] = RadioButton(choices[1],active=true); push!(f4,r4[1])
        r4[2] = RadioButton(r4[1],choices[2]);       push!(f4,r4[2])
        r4[3] = RadioButton(r4[2],choices[3]);       push!(f4,r4[3])
        r4[4] = RadioButton(r4[3],choices[4]);       push!(f4,r4[4])

        #define logo or version info or something
        #im=Gtk.GtkImage("rtmsim_logo1_h200px_grey.png")
        #im=Gtk.GtkLabel("RTMsim release 1.0.2")
        im=Gtk.GtkLabel(" ")

        #assembly elements in grid pattern
        g = GtkGrid()    #Cartesian coordinates, g[column,row]
        set_gtk_property!(g, :column_spacing, 5) 
        set_gtk_property!(g, :row_spacing, 5) 
        g[1,1]=sm; g[2,1] = mf; g[3,1] = pm;  g[4,1] = ps;  g[7,1] = in1;  g[8,1] = in2;  g[9,1] = in3;              
                g[2,2] = t;  g[3,2] = ss;  g[4,2] = cs; 
                g[2,3] = r;  g[3,3] = sel; g[4,3] = si; g[5,3] = ci; 
        g[1,4] = sr; g[2,4] = rf; g[3,4] = pr; g[4,4] = po;g[5,4] = pf;
        g[7:10,6:9] = im;
                                        g[3,11] = f1;   g[4,11] = f2;   g[5,11] = f3;   g[6,11] = f4;
        g[1,12] = par_1; g[2,12] = p0_1; g[3,12] = p1_1; g[4,12] = p2_1; g[5,12] = p3_1; g[6,12] = p4_1; 
        g[1,13] = par_2; g[2,13] = p0_2; g[3,13] = p1_2; g[4,13] = p2_2; g[5,13] = p3_2; g[6,13] = p4_2; 
        g[1,14] = par_3; g[2,14] = p0_3; g[3,14] = p1_3; g[4,14] = p2_3; g[5,14] = p3_3; g[6,14] = p4_3; 
                        g[2,15] = p0_4; g[3,15] = p1_4; g[4,15] = p2_4; g[5,15] = p3_4; g[6,15] = p4_4; 
                        g[2,16] = p0_5; g[3,16] = p1_5; g[4,16] = p2_5; g[5,16] = p3_5; g[6,16] = p4_5; 
                        g[2,17] = p0_6; g[3,17] = p1_6; g[4,17] = p2_6; g[5,17] = p3_6; g[6,17] = p4_6;      #g[9,17] = h; 
                        g[2,18] = p0_7; g[3,18] = p1_7; g[4,18] = p2_7; g[5,18] = p3_7; g[6,18] = p4_7;      g[9,18] = q; 
        push!(win, g)

        #callback functions
        function sm_clicked(w)
            #str = pick_file(pwd(),filterlist="bdf");
            if Sys.iswindows()
                str = pick_file(pwd(),filterlist="bdf");
            elseif Sys.islinux()
                str=open_dialog("Pick a file",GtkNullContainer(),("*.bdf",))
            end
            set_gtk_property!(mf,:text,str);
        end
        function sr_clicked(w)
            #str = pick_file(pwd(),filterlist="jld2");
            if Sys.iswindows()
                str = pick_file(pwd(),filterlist="jld2");
            elseif Sys.islinux()
                str=open_dialog("Pick a file",GtkNullContainer(),("*.jld2",))
            end
            set_gtk_property!(rf,:text,str);
        end
        function pm_clicked(w)
            str = get_gtk_property(mf,:text,String)
            rtmsim.plot_mesh(str,1)
        end
        function ps_clicked(w)
            str = get_gtk_property(mf,:text,String)
            rtmsim.plot_sets(str)
        end
        function sel_clicked(w)
            str = get_gtk_property(mf,:text,String)
            rtmsim.plot_mesh(str,2)
        end
        function ss_clicked(w)
            str1 = get_gtk_property(mf,:text,String); str2 = get_gtk_property(t,:text,String); str3 = get_gtk_property(par_3,:text,String); str4 = get_gtk_property(par_1,:text,String); str5 = get_gtk_property(par_2,:text,String);
            str11 = get_gtk_property(p0_1,:text,String); str12 = get_gtk_property(p0_2,:text,String); str13 = get_gtk_property(p0_3,:text,String); str14 = get_gtk_property(p0_4,:text,String); str15 = get_gtk_property(p0_5,:text,String); str16 = get_gtk_property(p0_6,:text,String); str17 = get_gtk_property(p0_7,:text,String);
            str21 = get_gtk_property(p1_1,:text,String); str22 = get_gtk_property(p1_2,:text,String); str23 = get_gtk_property(p1_3,:text,String); str24 = get_gtk_property(p1_4,:text,String); str25 = get_gtk_property(p1_5,:text,String); str26 = get_gtk_property(p1_6,:text,String); str27 = get_gtk_property(p1_7,:text,String); 
            str31 = get_gtk_property(p2_1,:text,String); str32 = get_gtk_property(p2_2,:text,String); str33 = get_gtk_property(p2_3,:text,String); str34 = get_gtk_property(p2_4,:text,String); str35 = get_gtk_property(p2_5,:text,String); str36 = get_gtk_property(p2_6,:text,String); str37 = get_gtk_property(p2_7,:text,String);
            str41 = get_gtk_property(p3_1,:text,String); str42 = get_gtk_property(p3_2,:text,String); str43 = get_gtk_property(p3_3,:text,String); str44 = get_gtk_property(p3_4,:text,String); str45 = get_gtk_property(p3_5,:text,String); str46 = get_gtk_property(p3_6,:text,String); str47 = get_gtk_property(p3_7,:text,String); 
            str51 = get_gtk_property(p4_1,:text,String); str52 = get_gtk_property(p4_2,:text,String); str53 = get_gtk_property(p4_3,:text,String); str54 = get_gtk_property(p4_4,:text,String); str55 = get_gtk_property(p4_5,:text,String); str56 = get_gtk_property(p4_6,:text,String); str57 = get_gtk_property(p4_7,:text,String);
            if [get_gtk_property(b,:active,Bool) for b in r1] == [true, false, false, false]; patchtype1val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, true, false, false]; patchtype1val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, false, true, false]; patchtype1val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, false, false, true]; patchtype1val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r2] == [true, false, false, false]; patchtype2val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, true, false, false]; patchtype2val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, false, true, false]; patchtype2val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, false, false, true]; patchtype2val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r3] == [true, false, false, false]; patchtype3val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, true, false, false]; patchtype3val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, false, true, false]; patchtype3val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, false, false, true]; patchtype3val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r4] == [true, false, false, false]; patchtype4val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, true, false, false]; patchtype4val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, false, true, false]; patchtype4val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, false, false, true]; patchtype4val=Int64(2); end;
            str61="0.01"; #str61 = get_gtk_property(r,:text,String)
            restartval=Int64(0); interactiveval=Int64(0); noutval=Int64(16); 
            rtmsim.rtmsim_rev1(1,str1,parse(Float64,str2), 1.01325e5,1.225,1.4,parse(Float64,str3), parse(Float64,str4),parse(Float64,str5), parse(Float64,str11),
            parse(Float64,str12),parse(Float64,str13),parse(Float64,str14),parse(Float64,str15),parse(Float64,str16),parse(Float64,str17),
            parse(Float64,str21),parse(Float64,str22),parse(Float64,str23),parse(Float64,str24),parse(Float64,str25),parse(Float64,str26),parse(Float64,str27), 
            parse(Float64,str31),parse(Float64,str32),parse(Float64,str33),parse(Float64,str34),parse(Float64,str35),parse(Float64,str36),parse(Float64,str37),
            parse(Float64,str41),parse(Float64,str42),parse(Float64,str43),parse(Float64,str44),parse(Float64,str45),parse(Float64,str46),parse(Float64,str47),
            parse(Float64,str51),parse(Float64,str52),parse(Float64,str53),parse(Float64,str54),parse(Float64,str55),parse(Float64,str56),parse(Float64,str57),
            patchtype1val,patchtype2val,patchtype3val,patchtype4val, restartval,"results.jld2", interactiveval,parse(Float64,str61), noutval);
        end
        function cs_clicked(w)
            str1 = get_gtk_property(mf,:text,String); str2 = get_gtk_property(t,:text,String); str3 = get_gtk_property(par_3,:text,String); str4 = get_gtk_property(par_1,:text,String); str5 = get_gtk_property(par_2,:text,String);
            str11 = get_gtk_property(p0_1,:text,String); str12 = get_gtk_property(p0_2,:text,String); str13 = get_gtk_property(p0_3,:text,String); str14 = get_gtk_property(p0_4,:text,String); str15 = get_gtk_property(p0_5,:text,String); str16 = get_gtk_property(p0_6,:text,String); str17 = get_gtk_property(p0_7,:text,String);
            str21 = get_gtk_property(p1_1,:text,String); str22 = get_gtk_property(p1_2,:text,String); str23 = get_gtk_property(p1_3,:text,String); str24 = get_gtk_property(p1_4,:text,String); str25 = get_gtk_property(p1_5,:text,String); str26 = get_gtk_property(p1_6,:text,String); str27 = get_gtk_property(p1_7,:text,String); 
            str31 = get_gtk_property(p2_1,:text,String); str32 = get_gtk_property(p2_2,:text,String); str33 = get_gtk_property(p2_3,:text,String); str34 = get_gtk_property(p2_4,:text,String); str35 = get_gtk_property(p2_5,:text,String); str36 = get_gtk_property(p2_6,:text,String); str37 = get_gtk_property(p2_7,:text,String);
            str41 = get_gtk_property(p3_1,:text,String); str42 = get_gtk_property(p3_2,:text,String); str43 = get_gtk_property(p3_3,:text,String); str44 = get_gtk_property(p3_4,:text,String); str45 = get_gtk_property(p3_5,:text,String); str46 = get_gtk_property(p3_6,:text,String); str47 = get_gtk_property(p3_7,:text,String); 
            str51 = get_gtk_property(p4_1,:text,String); str52 = get_gtk_property(p4_2,:text,String); str53 = get_gtk_property(p4_3,:text,String); str54 = get_gtk_property(p4_4,:text,String); str55 = get_gtk_property(p4_5,:text,String); str56 = get_gtk_property(p4_6,:text,String); str57 = get_gtk_property(p4_7,:text,String);
            if [get_gtk_property(b,:active,Bool) for b in r1] == [true, false, false, false]; patchtype1val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, true, false, false]; patchtype1val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, false, true, false]; patchtype1val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, false, false, true]; patchtype1val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r2] == [true, false, false, false]; patchtype2val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, true, false, false]; patchtype2val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, false, true, false]; patchtype2val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, false, false, true]; patchtype2val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r3] == [true, false, false, false]; patchtype3val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, true, false, false]; patchtype3val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, false, true, false]; patchtype3val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, false, false, true]; patchtype3val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r4] == [true, false, false, false]; patchtype4val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, true, false, false]; patchtype4val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, false, true, false]; patchtype4val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, false, false, true]; patchtype4val=Int64(2); end;
            str61="0.01"; #str61 = get_gtk_property(r,:text,String)
            restartval=Int64(1); interactiveval=Int64(0); noutval=Int64(16); 
            rtmsim.rtmsim_rev1(1,str1,parse(Float64,str2), 1.01325e5,1.225,1.4,parse(Float64,str3), parse(Float64,str4),parse(Float64,str5), parse(Float64,str11),
            parse(Float64,str12),parse(Float64,str13),parse(Float64,str14),parse(Float64,str15),parse(Float64,str16),parse(Float64,str17),
            parse(Float64,str21),parse(Float64,str22),parse(Float64,str23),parse(Float64,str24),parse(Float64,str25),parse(Float64,str26),parse(Float64,str27), 
            parse(Float64,str31),parse(Float64,str32),parse(Float64,str33),parse(Float64,str34),parse(Float64,str35),parse(Float64,str36),parse(Float64,str37),
            parse(Float64,str41),parse(Float64,str42),parse(Float64,str43),parse(Float64,str44),parse(Float64,str45),parse(Float64,str46),parse(Float64,str47),
            parse(Float64,str51),parse(Float64,str52),parse(Float64,str53),parse(Float64,str54),parse(Float64,str55),parse(Float64,str56),parse(Float64,str57),
            patchtype1val,patchtype2val,patchtype3val,patchtype4val, restartval,"results.jld2", interactiveval,parse(Float64,str61), noutval);
        end
        function si_clicked(w)
            str1 = get_gtk_property(mf,:text,String); str2 = get_gtk_property(t,:text,String); str3 = get_gtk_property(par_3,:text,String); str4 = get_gtk_property(par_1,:text,String); str5 = get_gtk_property(par_2,:text,String);
            str11 = get_gtk_property(p0_1,:text,String); str12 = get_gtk_property(p0_2,:text,String); str13 = get_gtk_property(p0_3,:text,String); str14 = get_gtk_property(p0_4,:text,String); str15 = get_gtk_property(p0_5,:text,String); str16 = get_gtk_property(p0_6,:text,String); str17 = get_gtk_property(p0_7,:text,String);
            str21 = get_gtk_property(p1_1,:text,String); str22 = get_gtk_property(p1_2,:text,String); str23 = get_gtk_property(p1_3,:text,String); str24 = get_gtk_property(p1_4,:text,String); str25 = get_gtk_property(p1_5,:text,String); str26 = get_gtk_property(p1_6,:text,String); str27 = get_gtk_property(p1_7,:text,String); 
            str31 = get_gtk_property(p2_1,:text,String); str32 = get_gtk_property(p2_2,:text,String); str33 = get_gtk_property(p2_3,:text,String); str34 = get_gtk_property(p2_4,:text,String); str35 = get_gtk_property(p2_5,:text,String); str36 = get_gtk_property(p2_6,:text,String); str37 = get_gtk_property(p2_7,:text,String);
            str41 = get_gtk_property(p3_1,:text,String); str42 = get_gtk_property(p3_2,:text,String); str43 = get_gtk_property(p3_3,:text,String); str44 = get_gtk_property(p3_4,:text,String); str45 = get_gtk_property(p3_5,:text,String); str46 = get_gtk_property(p3_6,:text,String); str47 = get_gtk_property(p3_7,:text,String); 
            str51 = get_gtk_property(p4_1,:text,String); str52 = get_gtk_property(p4_2,:text,String); str53 = get_gtk_property(p4_3,:text,String); str54 = get_gtk_property(p4_4,:text,String); str55 = get_gtk_property(p4_5,:text,String); str56 = get_gtk_property(p4_6,:text,String); str57 = get_gtk_property(p4_7,:text,String);
            if [get_gtk_property(b,:active,Bool) for b in r1] == [true, false, false, false]; patchtype1val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, true, false, false]; patchtype1val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, false, true, false]; patchtype1val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, false, false, true]; patchtype1val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r2] == [true, false, false, false]; patchtype2val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, true, false, false]; patchtype2val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, false, true, false]; patchtype2val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, false, false, true]; patchtype2val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r3] == [true, false, false, false]; patchtype3val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, true, false, false]; patchtype3val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, false, true, false]; patchtype3val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, false, false, true]; patchtype3val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r4] == [true, false, false, false]; patchtype4val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, true, false, false]; patchtype4val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, false, true, false]; patchtype4val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, false, false, true]; patchtype4val=Int64(2); end;
            str61 = get_gtk_property(r,:text,String)
            restartval=Int64(0); interactiveval=Int64(2); noutval=Int64(16); 
            rtmsim.rtmsim_rev1(1,str1,parse(Float64,str2), 1.01325e5,1.225,1.4,parse(Float64,str3), parse(Float64,str4),parse(Float64,str5), parse(Float64,str11),
            parse(Float64,str12),parse(Float64,str13),parse(Float64,str14),parse(Float64,str15),parse(Float64,str16),parse(Float64,str17),
            parse(Float64,str21),parse(Float64,str22),parse(Float64,str23),parse(Float64,str24),parse(Float64,str25),parse(Float64,str26),parse(Float64,str27), 
            parse(Float64,str31),parse(Float64,str32),parse(Float64,str33),parse(Float64,str34),parse(Float64,str35),parse(Float64,str36),parse(Float64,str37),
            parse(Float64,str41),parse(Float64,str42),parse(Float64,str43),parse(Float64,str44),parse(Float64,str45),parse(Float64,str46),parse(Float64,str47),
            parse(Float64,str51),parse(Float64,str52),parse(Float64,str53),parse(Float64,str54),parse(Float64,str55),parse(Float64,str56),parse(Float64,str57),
            patchtype1val,patchtype2val,patchtype3val,patchtype4val, restartval,"results.jld2", interactiveval,parse(Float64,str61), noutval);
        end
        function ci_clicked(w)
            str1 = get_gtk_property(mf,:text,String); str2 = get_gtk_property(t,:text,String); str3 = get_gtk_property(par_3,:text,String); str4 = get_gtk_property(par_1,:text,String); str5 = get_gtk_property(par_2,:text,String);
            str11 = get_gtk_property(p0_1,:text,String); str12 = get_gtk_property(p0_2,:text,String); str13 = get_gtk_property(p0_3,:text,String); str14 = get_gtk_property(p0_4,:text,String); str15 = get_gtk_property(p0_5,:text,String); str16 = get_gtk_property(p0_6,:text,String); str17 = get_gtk_property(p0_7,:text,String);
            str21 = get_gtk_property(p1_1,:text,String); str22 = get_gtk_property(p1_2,:text,String); str23 = get_gtk_property(p1_3,:text,String); str24 = get_gtk_property(p1_4,:text,String); str25 = get_gtk_property(p1_5,:text,String); str26 = get_gtk_property(p1_6,:text,String); str27 = get_gtk_property(p1_7,:text,String); 
            str31 = get_gtk_property(p2_1,:text,String); str32 = get_gtk_property(p2_2,:text,String); str33 = get_gtk_property(p2_3,:text,String); str34 = get_gtk_property(p2_4,:text,String); str35 = get_gtk_property(p2_5,:text,String); str36 = get_gtk_property(p2_6,:text,String); str37 = get_gtk_property(p2_7,:text,String);
            str41 = get_gtk_property(p3_1,:text,String); str42 = get_gtk_property(p3_2,:text,String); str43 = get_gtk_property(p3_3,:text,String); str44 = get_gtk_property(p3_4,:text,String); str45 = get_gtk_property(p3_5,:text,String); str46 = get_gtk_property(p3_6,:text,String); str47 = get_gtk_property(p3_7,:text,String); 
            str51 = get_gtk_property(p4_1,:text,String); str52 = get_gtk_property(p4_2,:text,String); str53 = get_gtk_property(p4_3,:text,String); str54 = get_gtk_property(p4_4,:text,String); str55 = get_gtk_property(p4_5,:text,String); str56 = get_gtk_property(p4_6,:text,String); str57 = get_gtk_property(p4_7,:text,String);
            if [get_gtk_property(b,:active,Bool) for b in r1] == [true, false, false, false]; patchtype1val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, true, false, false]; patchtype1val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, false, true, false]; patchtype1val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r1] == [false, false, false, true]; patchtype1val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r2] == [true, false, false, false]; patchtype2val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, true, false, false]; patchtype2val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, false, true, false]; patchtype2val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r2] == [false, false, false, true]; patchtype2val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r3] == [true, false, false, false]; patchtype3val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, true, false, false]; patchtype3val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, false, true, false]; patchtype3val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r3] == [false, false, false, true]; patchtype3val=Int64(2); end;
            if [get_gtk_property(b,:active,Bool) for b in r4] == [true, false, false, false]; patchtype4val=Int64(0);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, true, false, false]; patchtype4val=Int64(1);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, false, true, false]; patchtype4val=Int64(3);    elseif [get_gtk_property(b,:active,Bool) for b in r4] == [false, false, false, true]; patchtype4val=Int64(2); end;
            str61 = get_gtk_property(r,:text,String)
            restartval=Int64(1); interactiveval=Int64(2); noutval=Int64(16); 
            rtmsim.rtmsim_rev1(1,str1,parse(Float64,str2), 1.01325e5,1.225,1.4,parse(Float64,str3), parse(Float64,str4),parse(Float64,str5), parse(Float64,str11),
            parse(Float64,str12),parse(Float64,str13),parse(Float64,str14),parse(Float64,str15),parse(Float64,str16),parse(Float64,str17),
            parse(Float64,str21),parse(Float64,str22),parse(Float64,str23),parse(Float64,str24),parse(Float64,str25),parse(Float64,str26),parse(Float64,str27), 
            parse(Float64,str31),parse(Float64,str32),parse(Float64,str33),parse(Float64,str34),parse(Float64,str35),parse(Float64,str36),parse(Float64,str37),
            parse(Float64,str41),parse(Float64,str42),parse(Float64,str43),parse(Float64,str44),parse(Float64,str45),parse(Float64,str46),parse(Float64,str47),
            parse(Float64,str51),parse(Float64,str52),parse(Float64,str53),parse(Float64,str54),parse(Float64,str55),parse(Float64,str56),parse(Float64,str57),
            patchtype1val,patchtype2val,patchtype3val,patchtype4val, restartval,"results.jld2", interactiveval,parse(Float64,str61), noutval);
        end
        function pr_clicked(w)
            str = get_gtk_property(rf,:text,String)
            rtmsim.plot_results(str) 
        end
        function po_clicked(w)
            rtmsim.plot_overview(-1,16) 
        end
        function pf_clicked(w)
            rtmsim.plot_filling(-1,16) 
        end
        function q_clicked(w)
            #GLMakie.destroy!(GLMakie.global_gl_screen())
            Gtk.destroy(win)
        end
        #function h_clicked(w)
        #    i=GtkImage("rtmsim_help.png");
        #    w=GtkWindow(i,"Help");
        #    show(i);
        #end
        function in1_clicked(w)
            #str = pick_file(pwd(),filterlist="txt");
            if Sys.iswindows()
                str = pick_file(pwd(),filterlist="txt");
            elseif Sys.islinux()
                str=open_dialog("Pick a file",GtkNullContainer(),("*.txt",))
            end
            set_gtk_property!(in2,:text,str);
        end
        function in3_clicked(w)
            str = get_gtk_property(in2,:text,String)
            rtmsim.start_rtmsim(str)
        end

        #callbacks
        signal_connect(sm_clicked,sm,"clicked")
        signal_connect(sr_clicked,sr,"clicked")
        signal_connect(pm_clicked,pm,"clicked")
        signal_connect(ps_clicked,ps,"clicked")
        signal_connect(ss_clicked,ss,"clicked");
        signal_connect(cs_clicked,cs,"clicked")
        signal_connect(sel_clicked,sel,"clicked")
        signal_connect(si_clicked,si,"clicked");
        signal_connect(ci_clicked,ci,"clicked")
        signal_connect(pr_clicked,pr,"clicked")
        signal_connect(po_clicked,po,"clicked")
        signal_connect(pf_clicked,pf,"clicked")
        signal_connect(q_clicked,q,"clicked")
        #signal_connect(h_clicked,h,"clicked")
        signal_connect(in1_clicked,in1,"clicked")
        signal_connect(in3_clicked,in3,"clicked")

        #show GUI
        showall(win);
        if !isinteractive()
            c = Condition()
            signal_connect(win, :destroy) do widget
                notify(c)
            end
            wait(c)
        end


    end

end
