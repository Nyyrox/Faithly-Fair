import type { Hero, Product, Settings } from './types';
export const settings:Settings={business_name:'Faithly Fair',email:'Fairyfaithly@gmail.com',whatsapp:'',upi_id:'',upi_payee_name:'Faithly Fair'};
export const fallbackHero:Hero={eyebrow:'Flowers that speak from the heart',title:'Bouquets made for unforgettable moments.',description:'Fresh, expressive arrangements designed to turn every feeling into something beautiful.',cta_label:'Explore bouquets',cta_link:'/shop'};
export const fallbackProducts:Product[]=[
 {id:'demo-1',name:'Blushing Rose Bouquet',slug:'blushing-rose-bouquet',description:'Soft pink roses, seasonal greens and a flowing satin wrap.',price:899,stock_quantity:12,featured:true,active:true,display_order:1,category:'bouquet'},
 {id:'demo-2',name:'Ivory Garden Bouquet',slug:'ivory-garden-bouquet',description:'An elegant hand-tied mix in cream, blush and fresh green tones.',price:1299,stock_quantity:8,featured:true,active:true,display_order:2,category:'bouquet'},
 {id:'demo-3',name:'Petite Love Bouquet',slug:'petite-love-bouquet',description:'A charming compact bouquet for birthdays, thank-yous and just because.',price:649,stock_quantity:15,featured:true,active:true,display_order:3,category:'bouquet'},
 {id:'demo-4',name:'Sweetheart Gift Hamper',slug:'sweetheart-gift-hamper',description:'A secondary little luxury filled with treats and thoughtful keepsakes.',price:1499,stock_quantity:7,featured:false,active:true,display_order:4,category:'hamper'}
];
export const money=(n:number)=>new Intl.NumberFormat('en-NP',{style:'currency',currency:'NPR',maximumFractionDigits:0}).format(n);
