��/ * 	  
   *     T h i s   s c r i p t   i s   t o   b e   u s e d   w h e n   y o u   c h a n g e   y o u r   s e r v e r   D N S / D o m a i n   n a m e   o r   t h e   V 1   A p p   N a m e   ( o r   b o t h ) .  
   *     T h e   O l d S e r v e r S l u g   i s   w h a t e v e r   y o u r   p r e v i o u s   s e r v e r / a p p n a m e   v a l u e   u s e d   t o   b e   a n d   N e w S e r v e r S l u g   i s   w h a t e v e r   y o u r  
   *     n e w   s e r v e r / a p p n a m e   i s .  
   *      
   * 	 N O T E :     T h i s   s c r i p t   d e f a u l t s   t o   r o l l i n g   b a c k   c h a n g e s .  
   * 	 	 T o   c o m m i t   c h a n g e s ,   s e t   @ s a v e C h a n g e s   =   1 .  
   * /  
  
 d e c l a r e   @ s a v e C h a n g e s   b i t ;   - - s e t   @ s a v e C h a n g e s   =   1  
 d e c l a r e   @ s u p p o r t e d V e r s i o n s   v a r c h a r ( 1 0 0 0 ) ;   s e l e c t   @ s u p p o r t e d V e r s i o n s = ' 1 0 . 2 . * ,   1 0 . 3 . * ,   1 1 . * ,   1 2 . * ,   1 3 . * ,   1 4 . * ,   1 5 . * ,   1 6 . * , 17.*'  
  
 - -   E n s u r e   t h e   c o r r e c t   d a t a b a s e   v e r s i o n  
 B E G I N  
 	 d e c l a r e   @ s e p   c h a r ( 2 ) ;   s e l e c t   @ s e p = ' ,   '  
 	 i f   n o t   e x i s t s ( s e l e c t   *  
 	 	 f r o m   d b o . S y s t e m C o n f i g  
 	 	 j o i n   (  
 	 	 s e l e c t   S U B S T R I N G ( @ s u p p o r t e d V e r s i o n s ,   C . V a l u e + 1 ,   C H A R I N D E X ( @ s e p ,   @ s u p p o r t e d V e r s i o n s + @ s e p ,   C . V a l u e + 1 ) - C . V a l u e - 1 )   a s   V a l u e  
 	 	 f r o m   d b o . C o u n t e r   C  
 	 	 w h e r e   C . V a l u e   <   D a t a L e n g t h ( @ s u p p o r t e d V e r s i o n s )   a n d   S U B S T R I N G ( @ s e p + @ s u p p o r t e d V e r s i o n s ,   C . V a l u e + 1 ,   D a t a L e n g t h ( @ s e p ) )   =   @ s e p  
 	 	 )   V e r s i o n   o n   S y s t e m C o n f i g . V a l u e   l i k e   R E P L A C E ( V e r s i o n . V a l u e ,   ' * ' ,   ' % ' )   a n d   S y s t e m C o n f i g . N a m e   =   ' V e r s i o n '  
 	 )   b e g i n  
 	 	 	 r a i s e r r o r ( ' O n l y   s u p p o r t e d   o n   v e r s i o n ( s )   % s ' , 1 6 , 1 ,   @ s u p p o r t e d V e r s i o n s )  
 	 	 	 g o t o   D O N E  
 	 e n d  
 E N D  
  
 d e c l a r e   @ e r r o r   i n t ,   @ r o w c o u n t   i n t  
 s e t   n o c o u n t   o n ;   b e g i n   t r a n ;   s a v e   t r a n   T X  
  
  
 D E C L A R E   @ O l d S e r v e r S l u g   n v a r c h a r ( m a x )  
 D E C L A R E   @ N e w S e r v e r S l u g   n v a r c h a r ( m a x )  
  
 S E T   @ O l d S e r v e r S l u g   =   ' h t t p s : / / w w w . o l d V 1 h o s t . c o m / V e r s i o n O n e . W e b / '  
 S E T   @ N e w S e r v e r S l u g   =   ' h t t p : / / w w w . n e w V 1 h o s t . c o m / V 1 . W e b / '  
  
 - - S E L E C T   T O P   1 0 0 0   [ I D ]  
 - -             , [ V a l u e ]  
 - -     F R O M   [ d b o ] . [ L o n g S t r i n g ]  
 - -     W H E R E   [ V a l u e ]   l i k e   ' % '   +   @ N e w S e r v e r S l u g   +   ' % '  
  
 U P D A T E   [ d b o ] . [ L o n g S t r i n g ]  
 S E T   [ V a l u e ]   =   R E P L A C E ( c a s t ( [ V a l u e ]   a s   n v a r c h a r ( m a x ) ) ,   @ O l d S e r v e r S l u g ,   @ N e w S e r v e r S l u g )  
 W H E R E   [ V a l u e ]   l i k e   ' % '   +   @ O l d S e r v e r S l u g   +   ' % '  
  
  
  
 / *   a f t e r   e v e r y   m o d i f y i n g   s t a t e m e n t ,   c h e c k   f o r   e r r o r s ;   o p t i o n a l l y ,   e m i t   s t a t u s   * /  
 s e l e c t   @ r o w c o u n t = @ @ R O W C O U N T ,   @ e r r o r = @ @ E R R O R  
 i f   @ e r r o r < > 0   g o t o   E R R  
 r a i s e r r o r ( ' % d   r e c o r d s   u p d a t e d ' ,   0 ,   1 ,   @ r o w c o u n t )   w i t h   n o w a i t  
  
  
 i f   ( @ s a v e C h a n g e s   =   1 )   b e g i n   r a i s e r r o r ( ' C o m m i t t i n g   c h a n g e s ' ,   0 ,   2 5 4 ) ;   g o t o   O K   e n d  
 r a i s e r r o r ( ' T o   c o m m i t   c h a n g e s ,   s e t   @ s a v e C h a n g e s = 1 ' , 1 6 , 2 5 4 )  
 E R R :   r a i s e r r o r ( ' R o l l i n g   b a c k   c h a n g e s ' ,   0 ,   2 5 5 ) ;   r o l l b a c k   t r a n   T X  
 O K :   c o m m i t  
 D O N E : 
