/**
 * SpiderCluster - SpiderCluster console plugin.
 * @author Ian Norton
 * @verison 1.0 - 20010418.
 * @see JPanel
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
import javax.swing.text.*;
import javax.swing.event.*;
import java.awt.*;
import java.io.*;
import java.awt.event.*;
import java.util.Hashtable ;
import java.util.Enumeration ;

// public class Cluster extends Plugin implements Runnable
class SpiderCluster extends Plugin implements Runnable
    {
    // Name and tip used when creating the tabbed pane.
    public static final String NAME = "SpiderCluster" ;   
    public static final String TIP = "Spider DX Cluster Console" ;   
    
    // Number of commands to buffer.
    public static final int CMDBUFFERLINES = 30 ;

    // Number of lines of scrollback to buffer.
    public static final int SCROLLBUFFERLINES = 100 ;

    public static final boolean DEBUG = false ;

    // Input and output streams for the plugin.
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

    // Callsign of the connecting user.
    private String call ;

    private static final String encoding = "latin1"; // "ISO8859_1";

    /**
     * Class initialiser.
     **/
    public SpiderCluster()
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

        // Initialise the Scrolling output area.
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
                }
            public void removeUpdate(DocumentEvent e) { }
            public void changedUpdate(DocumentEvent e) { }
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
        tf.setCaretColor(Color.white) ;
    
        // Set the layout manager.
        this.setLayout(new BorderLayout()) ;

        // Scrollbars for scrolling text area.
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
                    if(DEBUG) System.out.println("Enter Event") ;
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
                    if(DEBUG) System.out.println("UP Event") ;
                    tf.setText(cbuf.getPreviousCommand()) ;
                    tf.setCaretPosition(tf.getText().length()) ;
                    }
                // DOWN Arrow
                if((e.getID() == KeyEvent.KEY_PRESSED) && (e.getKeyCode() == KeyEvent.VK_DOWN))
                    {
                    if(DEBUG) System.out.println("DOWN Event") ;
                    tf.setText(cbuf.getNextCommand()) ;
                    tf.setCaretPosition(tf.getText().length()) ;
                    }
                // Escape key
                if((e.getID() == KeyEvent.KEY_PRESSED) && (e.getKeyCode() == KeyEvent.VK_ESCAPE))
                    {
                    if(DEBUG) System.out.println("ESCAPE Event") ;
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

        // Prompt for callsign to connect with.
        while(call == null || call.indexOf(" ") > -1)
             {
             call = JOptionPane.showInputDialog("Enter your callsign") ;
             }

        call = call.toUpperCase() ;
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
        if(DEBUG) System.out.println("Cluster: send got : " + s) ;
 
        // If the input has no | in it, prefix I<CALLSIGN>| and send it.
        if(s.indexOf("|") == -1)
            {
            s = "I" + call + "|" + s ;
            }                                                                    
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
                // Read in a line of data (This screws up prompts with no /n)
                output = bir.readLine() ;
                if(output != null) display(output) ;

                if(DEBUG) System.out.println("After reading a line.") ;
                }
            catch(IOException ex)
                {
                System.out.println("SpiderCluster: IOException trying to read.") ;
                }
            } // End of infinate loop.
        } // End of run.                                                        

    private void display(String s)
        {
        // Automatic login - when we see "Conneted to" send the login string.
        if(s.startsWith("Connected to")) { send("A" + call + "|local\n") ; }
        
        // s = s.replace('', ' ') ;

        // Get rid of Ctrl-G's in UNICODE.
        while(s.indexOf("%07") > -1)
            {
            StringBuffer sb = new StringBuffer(s) ;
            sb.delete(s.indexOf("%07"), s.indexOf("%07") + 3) ;

            s = sb.toString() ;
            }

        // If the line has a | and starts with D, strip off upto and inc the |.
        if(s.indexOf("|") != -1 && s.charAt(0) == 'D')
            {
            s = s.substring(s.indexOf("|") + 1, s.length()) ;
            }
        
        // Find out what colour this needs to be.
        attr = getAttributes(s) ;

        // Display it in the doc.
        doc.append(s + "\n", attr) ;
        }

    /**
     * getAttributes(String s) - get attributes (i.e. colour) given a string.
     * @param String s
     **/
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
        h.put("DX de", Color.red) ;  // HF DX
        h.put(call + " de ", Color.magenta) ;
        // h.put("DX", Color.blue) ; // VHF/UHF DX
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
    } // End of class.
