/**
 * Console - modular Amateur Radio console for clusters and converse.
 * @author Ian Norton
 * @version 1.00 - 20010418.
 *
 * Copyright (C) 2001 Ian Norton.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public Licence as published by
 * the Free Software Foundation; either version 2 of the Licence, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public Licence for more details.
 *
 * You should have received a copy of the GNU General Public Licence
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Contacting the author :
 * Ian Norton
 * i.norton@lancaster.ac.uk
 * http://www.lancs.ac.uk/~norton/
 **/

import javax.swing.*;
import java.awt.*;
import java.awt.event.*;
import java.util.*;
import java.io.*;

public class Console
    {
    private JFrame frame ;
    private JPanel buttonpanel ;
    private JTabbedPane tabbedpane ;

    // Static variables.
    public static final int WIDTH  = 620 ;
    public static final int HEIGHT = 350 ;
    public static final String VERSION = "1.0" ;
    public static final String INFO = "RadioConsole Version " + VERSION +
                                      "\nWritten By Ian Norton (M0AZM)\n" +
                                      "i.norton@lancaster.ac.uk" ;

    // IO Multiplexors
    private PipedInputMUX inmux ;
    private PipedOutputMUX outmux ;
    
    // Vector to store plugins
    private Vector plugins ;

    private int plugnumber ;

    // Connection object.
    private Connection connection ;

    // Host that we connected to (May include port number).
    private String host ;

    /**
     * main
     **/
    public static void main(String[] args)
        {
        // Start the console.
        Console c = new Console("DX Cluster Console " + VERSION) ;
        }

    /**
     * Console init method.
     * @param String title
     **/
    public Console(String s)
        {
        // Default host and port to connect to.
        host = "127.0.0.1:27754" ;

        // Initialise the frame for the whole thing.
        frame = new JFrame(s) ;

        // Build connection here.
        PipedInputStream pincon = new PipedInputStream() ;
        PipedOutputStream poscon = new PipedOutputStream() ;
        connection = new Connection(pincon, poscon, this) ;

        // Build protocol here.
        /**
        PipedInputStream pinprot ;
        PipedOutputStream posprot ;
        try
            {
            pinprot = new PipedInputStream(poscon) ;
            posprot = new PipedOutputStream(pincon) ;
            Protocol protocol = new Protocol(pinprot, posprot, this) ;
            }
        catch(IOException ex)
            {
            System.out.println("Console: IOException creating protocol.") ;
            System.exit(1) ;
            }
        **/
        
        // Build input/output MUX's here.
        PipedInputStream pinmux ;
        PipedOutputStream posmux ;

        try
            {
            // Initialise pipes.
            pinmux = new PipedInputStream(poscon) ;
            posmux = new PipedOutputStream(pincon) ;

            // Initialise the MUX's
            inmux = new PipedInputMUX(posmux) ;
            outmux = new PipedOutputMUX(pinmux) ;
            }
        catch(IOException ex)
            {
            System.out.println("Console: IOException creating MUXes.") ;
            System.out.println(ex) ;
            System.exit(1) ;
            }

        // Initialise the plugin stuff.
        plugins = new Vector() ;
        plugnumber = 0 ;
        
        // Build tabbed panes from the plugins.
        buildTabs() ;

        // Build menu bars.
        buildMenus() ;

        // Build the button bar.
        // buildToolbar() ;

        // Add action listener to close the window.
        frame.addWindowListener(new WindowAdapter() {
            public void windowClosing(WindowEvent e) {
            System.exit(0) ; }
            });

        // Set initial size.
        frame.setSize(WIDTH, HEIGHT) ;
                                                                                
        frame.getContentPane().add(tabbedpane, BorderLayout.CENTER);
        frame.show();

        // Pop a connection dialog or use saved hostname or something here.
        connection.connect(host) ;
        }

    /**
     * buildTabs - build the tabbed panes with the plugins.
     **/
    public void buildTabs()
        {
        tabbedpane = new JTabbedPane() ;
        tabbedpane.setTabPlacement(JTabbedPane.BOTTOM);

        // The first plugin should always be the cluster plugin.
        // addPlugin("Cluster") ;
        addPlugin("SpiderCluster") ;
        
        // Call insert plugins method here. **AZM**

        }

    /**
     * buildMenus - build the Menus with the plugins.
     **/
    public void buildMenus()
        {
        // Create a menu bar and add it to the frame.
        JMenuBar mbar = new JMenuBar() ;
        frame.setJMenuBar(mbar) ;
 
        // Create the file menu stuff.
        JMenu filemenu = new JMenu("File") ;

        JMenuItem item ;
        filemenu.add(item = new JMenuItem("Connect")) ;
        item.setMnemonic(KeyEvent.VK_C) ;
        item.setAccelerator(KeyStroke.getKeyStroke(
                KeyEvent.VK_C, ActionEvent.ALT_MASK));
        item.addActionListener(new ActionListener() { 
        public void actionPerformed(ActionEvent e) { 
                connection.connect(host);
        }});

        filemenu.add(item = new JMenuItem("Connect To")) ;
        // item.setMnemonic(KeyEvent.VK_C) ;
        // item.setAccelerator(KeyStroke.getKeyStroke(
        //           KeyEvent.VK_C, ActionEvent.ALT_MASK));
        item.addActionListener(new ActionListener() { 
        public void actionPerformed(ActionEvent e) { 
            // Connection dialog.
            String ho = JOptionPane.showInputDialog("Enter the host to connect to") ;
            if(ho == null || ho.indexOf(" ") > -1)
                return ;

            if(ho != null && ho.length() > 0)
                {
                // connection.disconnect() ;
                connection.connect(ho);
                }
        }});

        filemenu.add(item = new JMenuItem("Disconnect")) ;
        item.addActionListener(new ActionListener() {
        public void actionPerformed(ActionEvent e) 
            { connection.disconnect() ; }});

        filemenu.add(item = new JMenuItem("About")) ;
        item.addActionListener(new ActionListener() {
        public void actionPerformed(ActionEvent e) 
            { JOptionPane.showMessageDialog(frame, INFO) ; }});

        filemenu.addSeparator() ;

        filemenu.add(item = new JMenuItem("Quit")) ;
        item.addActionListener(new ActionListener() { // Quit.
        public void actionPerformed(ActionEvent e) { System.exit(0) ; }});

        // Add the menus onto the menu bar.
        mbar.add(filemenu) ;
        }

    /**
     * buildToolbar - build the Toolbar with the plugins.
     **/
    public void buildToolbar()
        {
        
        }

    /**
     * addPlugin
     * @param String - name of the plugin to insert.
     **/
    private void addPlugin(String p)
        {
        Plugin pl = null ;
        
        try
            {
            Class c = Class.forName(p) ;
            pl = (Plugin)c.newInstance();
            }
        catch(ClassNotFoundException ex)
            {
            System.out.println("Exceptional!\n"+ex) ;
            }
        catch(InstantiationException ex)
            {
            System.out.println("Exceptional!\n"+ex) ;
            }
        catch(IllegalAccessException ex)
            {
            System.out.println("Exceptional!\n"+ex) ;
            }

        PipedOutputStream plugoutstr = new PipedOutputStream() ;
        PipedInputStream pluginstr = new PipedInputStream() ;

        // Insert the object into the vector.
        plugins.addElement(pl) ;

        // Add the plug in to the tabbedpane.
        tabbedpane.addTab(pl.getTabName(), null, pl, pl.getTabTip()) ;

        PipedInputStream pinmux = null ;
        PipedOutputStream posmux = null ;

        try
            {
            pinmux = new PipedInputStream(plugoutstr) ;
            posmux = new PipedOutputStream(pluginstr) ;
            }
        catch(IOException ex)
            {
            System.out.println("Console: IOException creating plugin pipes.") ;
            System.out.println(ex) ;
            }

        // Add the streams to the multiplexors.
        inmux.addInputStream(pinmux) ;
        outmux.addOutputStream(posmux) ;

        // Initialise the plugin.
        pl.init(pluginstr, plugoutstr) ;

        plugnumber++ ;

        // Menus?

        // Toolbars?
        }
    }

