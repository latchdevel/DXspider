/**
 * Cluster - Cluster console plugin.
 * @author Ian Norton
 * @verison 0.1 - 28/12/00.
 * @see JPanel
 * 
 * RadioConsole.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.                     *
 * Contacting the author :
 * Ian Norton
 * i.norton@lancaster.ac.uk
 * http://www.lancs.ac.uk/~norton/
 **/

import javax.swing.*;
import javax.swing.text.*;
import javax.swing.event.*;
import java.awt.*;
import java.io.*;
import java.awt.event.*;
import java.util.Hashtable ;
import java.util.Enumeration ;

// public class Cluster extends Plugin implements Runnable
class Cluster extends Plugin implements Runnable
    {
    // Name and tip used when creating the tabbed pane.
    public static final String NAME = "Cluster" ;   
    public static final String TIP = "DX Cluster Console" ;   
    
    // Number of commands to buffer.
    public static final int CMDBUFFERLINES = 30 ;

    // Number of lines of scrollback to buffer.
    public static final int SCROLLBUFFERLINES = 100 ;

    public static final boolean DEBUG = false ;

    // Input and output streams for the plugin.
    // private PipedInputStream pin ;
    private BufferedReader bir ;
    private PipedOutputStream pos ;

    // User input field.
    private JTextField tf ;

    private JTextPane jtp ;
    private Thread t ;
    private SimpleAttributeSet attr ;
    private LimitedStyledDocument doc ;

    // Input line scrollback buffer.
    private CommandBuffer cbuf ;

    private static final String encoding = "latin1"; // "ISO8859_1";

    /**
     * Class initialiser.
     **/
    public Cluster()
        {
        super() ;
        }   

    /**
     * Plugin initialiser.
     * @param PipedInputStream i - Stream to read data from
     * @param PipedOutputStream o - Stream to write data to
     **/
    public void init(PipedInputStream i, PipedOutputStream o)
        {
        // Initialise the plugin IO.
        bir = new BufferedReader(new InputStreamReader(i)) ;
        pos = o ;

        // Initialise the ScrollingTextArea.
        // ScrollingTextArea sta = new ScrollingTextArea(pin, SCROLLBUFFERLINES, doc) ;
        // sta.setFont(new Font("Courier", Font.PLAIN, 10)) ;
        // sta.setFont(new Font("Monospaced", Font.PLAIN, 10)) ;
        // System.out.println(sta.getFont()) ;

        doc = new LimitedStyledDocument(SCROLLBUFFERLINES) ;
        jtp = new JTextPane(doc) ;
        jtp.setEditable(false) ;
        attr = new SimpleAttributeSet() ;
        StyleConstants.setFontFamily(attr, "Monospaced") ;
        StyleConstants.setFontSize(attr, 10) ;
        jtp.setBackground(Color.black) ;

        doc.addDocumentListener(new DocumentListener() {
            public void insertUpdate(DocumentEvent e) {
                jtp.setCaretPosition(doc.getLength()) ;
                // tf.requestFocus() ;
                }
            public void removeUpdate(DocumentEvent e) {
                }
            public void changedUpdate(DocumentEvent e) {
                }
            });

        // Initialise the TextField for user input.
        tf = new JTextField() ;
        tf.setFont(new Font("Courier", Font.PLAIN, 10)) ;
        Insets inset = tf.getMargin() ;
        inset.top = inset.top + 1 ;
        inset.bottom = inset.bottom + 1 ;
        tf.setMargin(inset) ;
        tf.setForeground(Color.white) ;
        tf.setBackground(Color.black) ;

        // Set the layout manager.
        this.setLayout(new BorderLayout()) ;

        // Scrollbars for scrolling text area.
        // JScrollPane scrollpane = new JScrollPane(sta);
        JScrollPane scrollpane = new JScrollPane(jtp);

        // Add the bits to the panel.
        this.add(scrollpane, BorderLayout.CENTER);
        this.add(tf, BorderLayout.SOUTH);

        // Initialise the command buffer.
        cbuf = new CommandBuffer(CMDBUFFERLINES) ;

        // Action listener stuff.
        tf.addKeyListener(new KeyAdapter()
            {
            public void keyTyped(KeyEvent e)
                {
                // Enter key
                if((e.getID() == KeyEvent.KEY_TYPED) && (e.getKeyChar() == KeyEvent.VK_ENTER))
                    {
                    // System.out.println("Enter Event") ;
                    send(tf.getText() + '\n') ;
                    cbuf.addCommand(tf.getText()) ;
                    tf.setText("") ;
                    }
                }
            public void keyPressed(KeyEvent e)
                {
                // UP Arrow
                if((e.getID() == KeyEvent.KEY_PRESSED) && (e.getKeyCode() == KeyEvent.VK_UP))
                    {
                    // System.out.println("UP Event") ;
                    tf.setText(cbuf.getPreviousCommand()) ;
                    tf.setCaretPosition(tf.getText().length()) ;
                    }
                // DOWN Arrow
                if((e.getID() == KeyEvent.KEY_PRESSED) && (e.getKeyCode() == KeyEvent.VK_DOWN))
                    {
                    // System.out.println("DOWN Event") ;
                    tf.setText(cbuf.getNextCommand()) ;
                    tf.setCaretPosition(tf.getText().length()) ;
                    }
                // Escape key
                if((e.getID() == KeyEvent.KEY_PRESSED) && (e.getKeyCode() == KeyEvent.VK_ESCAPE))
                    {
                    // System.out.println("ESCAPE Event") ;
                    tf.setText("") ;                                                                }
                }
            }) ;
 
        // Add component listener to focus text field.
        this.addComponentListener(new ComponentAdapter() {
            public void componentShown(ComponentEvent e) {
                tf.setVisible(true) ;
                tf.requestFocus() ;
                }
            });
        
        // Init the scrolling thread.
        t = new Thread(this, "Scrolling thread") ;
        t.start() ;
        } // End of init
 
    /**
     * getTabName - Get the name that this component should show on it's tab
     * @returns String s - Tab name
     **/
 
    public String getTabName()
        {                                                                               return NAME ;
        }
 
    /**
     * getTabTip - Get the tip that this component should show on it's tab
     * @returns String s - Tab tip
     **/
    public String getTabTip()
        {
        return TIP ;
        }
 
    /**
     * getMenu - get the menu to add to the main menu bar.
     * @returns JMenu
     **/
    public JMenu getMenu()
        {
        return null ;
        }                                                                        
    /**
     * send - Helper function to send data out to the PipedOutputMUX
     * @param String s - data to send.
     **/
    private void send(String s)
        {
        // System.out.println("Cluster: send got : " + s) ;
 
        try
            {
            // Write the data to the stream.
            for(int i=0;i<s.length();i++)
                {
                pos.write(s.charAt(i)) ;
                }
            }
        catch(IOException ex)
            {
            System.out.println("Cluster: IOException on destination stream.") ;
            System.out.println(ex) ;
            }
        }
 
    /**
     * Loop continually checking to see if anything has been written to the
     * file that is being monitored.
     */
    public void run()
        {
        String output = new String() ;
        // Loop continually reading from the input stream
        while(true)                                                          
            {
            
            try
                {
                //while(n >= 0)
                //    {
                //    n = pin.read(b);
                //    if(n > 0)
                //        {
                //        output = new String(b, 0, n, encoding) ;
                //        display(output) ;
                //        // System.out.println("Read : " + output) ;
                //        }
                //    }
                output = bir.readLine() ;
                if(output != null) display(output) ;

                if(DEBUG) System.out.println("After reading a line.") ;
                }
            catch(IOException ex)
                {
                System.out.println("ScrollingTextArea: IOException trying to read.") ;
                }
            } // End of infinate loop.
        } // End of run.                                                        

    private void display(String s)
        {
        // System.out.println(s) ;
        // Ignore Ctrl-G.
        // s = s.replace('\r', ' ') ;
        s = s.replace('', ' ') ;                                              

        attr = getAttributes(s) ;
        doc.append(s + "\n", attr) ;
        }

    private SimpleAttributeSet getAttributes(String s)
        {
        SimpleAttributeSet sas = attr ;

        /**
         # 0 - $foreground, $background
         # 1 - RED, $background
         # 2 - BROWN, $background
         # 3 - GREEN, $background
         # 4 - CYAN, $background
         # 5 - BLUE, $background
         # 6 - MAGENTA, $background

        VHF DX SPOT
         [ '^DX de [\-A-Z0-9]+:\s+([57][01]\d\d\d\.|\d\d\d\d\d\d+.)', COLOR_PAIR(1) ],
        PROMPT
         [ '^G0VGS de GB7MBC', COLOR_PAIR(6) ],
        DUNNO!
         [ '^G0VGS de', A_BOLD|COLOR_PAIR(2) ],
        HF DX SPOT
         [ '^DX', COLOR_PAIR(5) ],
        ANNOUNCE
         [ '^To', COLOR_PAIR(3) ],
        WWV SPOT
         [ '^WWV', COLOR_PAIR(4) ],
        DUNNO! 
         [ '^[-A-Z0-9]+ de [-A-Z0-9]+ \d\d-\w\w\w-\d\d\d\d \d\d\d\dZ', COLOR_PAIR(0) ],
        DUNNO! - PROBABLY A TALK
         [ '^[-A-Z0-9]+ de [-A-Z0-9]+ ', COLOR_PAIR(6) ],
        WX SPOT
         [ '^WX', COLOR_PAIR(3) ],
        NEW MAIL
         [ '^New mail', A_BOLD|COLOR_PAIR(4) ],
        USER LOGIN?
         [ '^User', COLOR_PAIR(2) ],
        NODE LOGIN?
         [ '^Node', COLOR_PAIR(2) ],                                  
         **/

        Hashtable h = new Hashtable() ;
        h.put("DX de", Color.red) ;
        h.put("M0AZM de GB7MBC", Color.magenta) ;
        h.put("G0VGS de GB7MBC", Color.magenta) ;
        h.put("G0VGS2 de GB7MBC", Color.magenta) ;
        // h.put("DX", Color.blue) ;
        h.put("To", Color.green) ;
        h.put("WWV", Color.cyan) ;
        h.put("WCY", Color.cyan) ;
        // h.put("", Color.) ;
        // h.put("", Color.) ;
        h.put("WX", Color.green) ;
        h.put("New mail", Color.cyan) ;
        //h.put("User", Color.brown) ;
        //h.put("Node", Color.brown) ;
        h.put("User", Color.yellow) ;
        h.put("Node", Color.orange) ;
        
        Enumeration e = h.keys() ;
        
        while(e.hasMoreElements())
            {
            String prefix = (String)e.nextElement() ;
            if(s.startsWith(prefix))
                {
                StyleConstants.setForeground(sas, (Color)h.get(prefix)) ;
                return sas ;
                }
            }

        StyleConstants.setForeground(sas, Color.white) ;
        return sas ;
        }
    }
